WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age >= 84
    AND anchor_age <= 94
),
acs_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM eligible_patients ep
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ep.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE d.seq_num = 1
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code = '4111'))
      OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code = 'I200'))
    )
),
troponin_labs AS (
  SELECT
    le.hadm_id,
    le.charttime,
    le.valuenum,
    le.ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN acs_admissions aa
    ON le.hadm_id = aa.hadm_id
  WHERE le.itemid = 33564
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
    AND le.ref_range_upper IS NOT NULL
),
initial_troponin AS (
  SELECT
    hadm_id,
    valuenum AS initial_troponin,
    ref_range_upper
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
    FROM troponin_labs
  )
  WHERE rn = 1
    AND valuenum > ref_range_upper
)
SELECT
  COUNT(*) AS n_admissions,
  AVG(it.initial_troponin) AS mean_initial_troponin,
  APPROX_PERCENTILE(it.initial_troponin, 0.25) AS q1_initial_troponin,
  APPROX_PERCENTILE(it.initial_troponin, 0.5) AS median_initial_troponin,
  APPROX_PERCENTILE(it.initial_troponin, 0.75) AS q3_initial_troponin
FROM initial_troponin AS it;