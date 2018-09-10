defmodule Bep.BearController do
  use Bep.Web, :controller
  alias Bep.{BearAnswers, BearQuestion, PicoSearch, Publication, Search, User}

  @in_light "In light of the above assessment,"
  @further "Any further comments?"

  def index(conn, _) do
    user = conn.assigns.current_user
    searches =
      User.get_all_notes(user).searches
      |> Search.group_searches_by_day()
      |> Enum.filter(fn({_date, searches}) ->
        Enum.any?(searches, &has_publications?/1)
      end)
      |> Enum.map(fn({date, searches}) ->
        filtered_searches =
          searches
          |> Enum.filter(&has_publications?/1)
          |> add_pico_search_id_to_searches()

        {date, filtered_searches}
      end)

    render(conn, "index.html", searches: searches)
  end

  def complete(conn, %{"publication_id" => pub_id, "pico_search_id" => ps_id}) do
    render(conn, :complete, pub_id: pub_id, ps_id: ps_id)
  end

  def paper_details(conn, %{"publication_id" => pub_id, "pico_search_id" => ps_id}) do
    changeset = BearAnswers.changeset(%BearAnswers{})
    questions = BearQuestion.all_questions_for_sec(pub_id, "paper_details")
    publication = Repo.get!(Publication, pub_id)

    assigns = [
      changeset: changeset,
      publication: publication,
      questions: questions,
      pico_search_id: ps_id
    ]

    render(conn, :paper_details, assigns)
  end

  def check_validity(conn, %{"pico_search_id" => ps_id, "publication_id" => pub_id}) do
    changeset = BearAnswers.changeset(%BearAnswers{})
    all_questions = BearQuestion.all_questions_for_sec(pub_id, "check_validity")
    in_light_question = Enum.find(all_questions, &(&1.question =~ @in_light))

    outcomes =
      ps_id
      |> PicoSearch.get_related_pico_outcomes()
      |> get_outcome_answers_for_question(in_light_question, pub_id)

    further_question = Enum.find(all_questions, &(&1.question =~ @further))
    questions =
      all_questions
      |> Enum.reject(&(&1.question =~ @in_light))
      |> Enum.reject(&(&1.question =~ @further))

    question_nums = 1..length(questions)

    assigns = [
      changeset: changeset,
      questions: Enum.zip(question_nums, questions),
      in_light: in_light_question,
      further: further_question,
      pub_id: pub_id,
      pico_search_id: ps_id,
      outcomes: outcomes
    ]

    render(conn, :check_validity, assigns)
  end

  def calculate_results(conn,  %{"pico_search_id" => ps_id, "publication_id" => pub_id}) do
    changeset = BearAnswers.changeset(%BearAnswers{})
    questions = BearQuestion.all_questions_for_sec(pub_id, "calculate_results")
    yes_no_questions = Enum.take(questions, 4)
    [inter_yes, inter_no, control_yes, control_no] = yes_no_questions
    note_question = Enum.find(questions, &(&1.question =~ "Notes"))
    pico_outcomes = PicoSearch.get_related_pico_outcomes(ps_id)

    pico_answers_queries =
      pico_outcomes
      |> Enum.map(fn(po) ->
        from ba in BearAnswers,
        where: (ba.bear_question_id == ^control_yes.id
        or ba.bear_question_id == ^control_no.id
        or ba.bear_question_id == ^inter_yes.id
        or ba.bear_question_id == ^inter_no.id)
        and ba.publication_id == ^pub_id
        and ba.index == ^po.o_index,
        order_by: [desc: ba.id],
        limit: 4
      end)

    updated_outcomes =
      case pico_outcomes do
        [] ->
          []
        _ ->
          1..length(pico_outcomes)
          |> Enum.map(fn(index) ->
            pico_outcome =
              pico_outcomes
              |> Enum.at(index - 1)
              |> Map.put(:questions, [
                inter_yes.id, inter_no.id, control_yes.id, control_no.id
              ])

            pico_answers_query = Enum.at(pico_answers_queries, index - 1)

            pico_outcome_answers =
              pico_answers_query
              |> Repo.all()
              |> Enum.sort(&(&1.bear_question_id < &2.bear_question_id))

            case pico_outcome_answers do
              [] ->
                Map.put(pico_outcome, :answers, ["", "", "", ""])
              [ans1, ans2, ans3, ans4] ->
                Map.put(
                  pico_outcome,
                  :answers,
                  [ans1.answer, ans2.answer, ans3.answer, ans4.answer]
                )
              _ ->
                Map.put(pico_outcome, :answers, ["", "", "", ""])
            end
          end)
      end

    assigns = [
      changeset: changeset,
      pub_id: pub_id,
      pico_search_id: ps_id,
      note_question: note_question,
      updated_outcomes: updated_outcomes
    ]

    render(conn, :calculate_results, assigns)
  end

  def relevance(conn, %{"pico_search_id" => ps_id, "publication_id" => pub_id}) do
    changeset = BearAnswers.changeset(%BearAnswers{})
    question_nums = 1..3
    all_questions = BearQuestion.all_questions_for_sec(pub_id, "relevance")

    {first_three, rest} = Enum.split(all_questions, 3)
    {[prob, comment], dates} = Enum.split(rest, 2)

    assigns = [
      changeset: changeset,
      pub_id: pub_id,
      pico_search_id: ps_id,
      first_three: Enum.zip(question_nums, first_three),
      prob: prob,
      comment: comment,
      dates: dates
    ]

    render(conn, :relevance, assigns)
  end

  # create bear_answers
  def create(conn, %{"next" => page, "bear_answers" => bear_answers}) do
    %{"pub_id" => pub_id, "pico_search_id" => ps_id} = bear_answers
    insert_bear_answers(bear_answers, pub_id, ps_id)
    redirect_path = get_path(conn, page, pub_id, ps_id)
    redirect(conn, to: redirect_path)
  end

  # save and continue later route for bear_form
  def create(conn, %{"pub_id" => pub_id, "pico_search_id" => ps_id} = params) do
    insert_bear_answers(params, pub_id, ps_id)
    redirect(conn, to: search_path(conn, :index))
  end

  # HELPERS
  def get_outcome_answers_for_question(outcomes, question, pub_id) do
    outcomes
    |> Enum.map(fn(po) ->
      query =
        from ba in BearAnswers,
        where: ba.bear_question_id == ^question.id
        and ba.publication_id == ^pub_id
        and ba.index == ^po.o_index,
        order_by: [desc: ba.id],
        limit: 1

      bear_ans = Repo.one(query)
      case bear_ans do
        nil ->
          Map.put(po, :answer, "")
        _ ->
          Map.put(po, :answer, bear_ans.answer)
      end
    end)
  end

  def get_path(conn, page, pub_id, ps_id) do
    assigns = [publication_id: pub_id, pico_search_id: ps_id]
    case page do
      "check_validity" ->
        bear_path(conn, :check_validity, assigns)

      "calculate_results" ->
        bear_path(conn, :calculate_results, assigns)

      "relevance" ->
        bear_path(conn, :relevance, assigns)

      "complete_bear" ->
        bear_path(conn, :complete, assigns)
    end
  end

  def insert_bear_answers(params, pub_id, ps_id) do
    pub = Repo.get(Publication, pub_id)
    pico_search = Repo.get(PicoSearch, ps_id)

    params
    |> make_q_and_a_list()
    |> Enum.map(&BearAnswers.insert_ans(%BearAnswers{}, &1, pub, pico_search))
  end

  def make_q_and_a_list(params) do
    params
    |> Map.keys()
    |> Enum.filter(&(&1 =~ "q_"))
    |> Enum.map(fn(key) ->

      {bear_q_id, o_index} = get_bear_q_id_and_o_index(key)
      answer = params |> Map.get(key) |> date_to_str()

      if answer != "", do: {answer, bear_q_id, o_index}

    end)
  end

  def date_to_str(answer) do
    if is_map(answer) do
      "#{answer["day"]}/#{answer["month"]}/#{answer["year"]}"
    else
      answer
    end
  end

  def get_bear_q_id_and_o_index(key) do
    str = key |> String.trim_leading("q_")

    case String.contains?(str, "o_index") do
      true ->
        [bear_q_id, _, _, o_index] = String.split(str, "_")
        {bear_q_id, o_index}
      false ->
        {str, nil}
    end
  end

  # HELPERS
  defp has_publications?(search) do
    search.publications !== [] && search.uncertainty == true
  end

  defp add_pico_search_id_to_searches(searches) do
    Enum.reduce(searches, [], fn(search, acc) ->
      note_search = search.note_searches
      pico_search = Repo.get_by(PicoSearch, note_search_id: note_search.id)

      case pico_search == nil do
        true ->
          [acc]
        false ->
          updated_ns = Map.put(note_search, :pico_search_id, pico_search.id)
          updated_search = Map.put(search, :note_searches, updated_ns)

          [updated_search, acc]
          |> Enum.reverse()
          |> List.flatten()
      end
    end)
  end
end
