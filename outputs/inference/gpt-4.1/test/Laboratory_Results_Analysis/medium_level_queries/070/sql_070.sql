WITH male_90_100 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 90 AND 100
),
chest_pain_admissions AS (
  -- ICD-10: R07.9, R07.1, R07.2, R07.89; ICD-9: 786.50, 786.51, 786.52, 786.59
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (
    (d.icd_version = 9 AND d.icd_code IN ('78650','78651','78652','78659'))
    OR
    (d.icd_version = 10 AND d.icd_code IN ('R079','R071','R072','R0789'))
  )
),
troponin_i_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom,
    l.ref_range_upper,
    d_lab.label
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_lab
    ON l.itemid = d_lab.itemid
  WHERE LOWER(d_lab.label) LIKE '%troponin i%'
    AND l.valuenum IS NOT NULL
),
initial_troponin AS (
  -- Get the first Troponin I value per admission
  SELECT
    t.subject_id,
    t.hadm_id,
    t.charttime,
    t.valuenum,
    t.valueuom,
    t.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY t.subject_id, t.hadm_id ORDER BY t.charttime ASC) AS rn
  FROM troponin_i_labs t
),
cohort AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.charttime,
    i.valuenum,
    i.valueuom,
    i.ref_range_upper
  FROM initial_troponin i
  JOIN male_90_100 m ON i.subject_id = m.subject_id
  JOIN chest_pain_admissions c ON i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id
  WHERE i.rn = 1
    -- Elevated: if ref_range_upper is available, use it; else use clinical threshold 0.04 ng/mL
    AND (
      (i.ref_range_upper IS NOT NULL AND i.valuenum > i.ref_range_upper)
      OR
      (i.ref_range_upper IS NULL AND i.valuenum > 0.04)
    )
)
SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS p75,
  MAX(valuenum) - MIN(valuenum) AS `range`
FROM cohort;