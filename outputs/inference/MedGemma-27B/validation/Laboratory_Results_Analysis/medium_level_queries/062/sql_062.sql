WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 46 AND 56
),
Admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientInfo AS p ON a.subject_id = p.subject_id
),
TnTResults AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    l.charttime,
    l.valuenum AS tnt_value,
    l.valueuom AS tnt_uom,
    l.itemid
  FROM
    Admissions AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS l ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
  WHERE
    l.itemid = 50178 -- hs-TnT
),
FirstTnT AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(charttime) AS first_tnt_charttime
  FROM
    TnTResults
  GROUP BY
    subject_id,
    hadm_id
),
TnTValues AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    t.charttime,
    t.tnt_value,
    t.tnt_uom,
    ft.first_tnt_charttime
  FROM
    TnTResults AS t
  INNER JOIN
    FirstTnT AS ft ON t.subject_id = ft.subject_id AND t.hadm_id = ft.hadm_id AND t.charttime = ft.first_tnt_charttime
),
TnTInterpretation AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN tnt_value < 0.01 THEN 'Normal'
      WHEN tnt_value BETWEEN 0.01 AND 0.09 THEN 'Borderline'
      ELSE 'Myocardial Injury'
    END AS tnt_interpretation
  FROM
    TnTValues
  WHERE
    tnt_uom = 'ng/mL'
)
SELECT
  tnt_interpretation,
  COUNT(DISTINCT t.subject_id) AS patient_count,
  COUNT(DISTINCT t.hadm_id) AS admission_count,
  AVG(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS mean_los_days
FROM
  Admissions AS a
INNER JOIN
  TnTInterpretation AS t ON a.subject_id = t.subject_id AND a.hadm_id = t.hadm_id
GROUP BY
  tnt_interpretation
ORDER BY
  tnt_interpretation;