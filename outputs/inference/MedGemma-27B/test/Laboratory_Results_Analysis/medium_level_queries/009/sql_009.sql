WITH RelevantLabs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS hs_tnt_value,
    l.valueuom AS hs_tnt_uom
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  WHERE
    d.label = 'Troponin I, high-sensitivity'
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL'
),
FilteredAdmissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),
FirstTnT AS (
  SELECT
    rl.subject_id,
    rl.hadm_id,
    rl.hs_tnt_value
  FROM
    RelevantLabs AS rl
  INNER JOIN
    FilteredAdmissions AS fa
    ON rl.subject_id = fa.subject_id
    AND rl.hadm_id = fa.hadm_id
  WHERE
    rl.hs_tnt_value > 0.014
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY rl.subject_id, rl.hadm_id ORDER BY rl.charttime ASC) = 1
)
SELECT
  PERCENTILE_CONT(0.25, hs_tnt_value) AS percentile_25,
  PERCENTILE_CONT(0.50, hs_tnt_value) AS percentile_50,
  PERCENTILE_CONT(0.75, hs_tnt_value) AS percentile_75,
  MIN(hs_tnt_value) AS min_hs_tnt,
  MAX(hs_tnt_value) AS max_hs_tnt
FROM
  FirstTnT;