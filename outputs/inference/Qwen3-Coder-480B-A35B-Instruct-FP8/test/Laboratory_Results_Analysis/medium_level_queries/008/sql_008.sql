WITH troponin_t AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents le
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems di
    ON le.itemid = di.itemid
  WHERE
    LOWER(di.label) = 'troponin t'
    AND le.valuenum IS NOT NULL
    AND le.valuenum >= 0
),
first_troponin AS (
  SELECT
    subject_id,
    hadm_id,
    troponin_value
  FROM
    troponin_t
  WHERE
    rn = 1
),
acs_admissions AS (
  SELECT DISTINCT
    di.subject_id,
    di.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    REGEXP_CONTAINS(LOWER(d.long_title), r'(suspected|rule[- ]out|unstable|angina)')
),
eligible_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    ft.troponin_value
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN
    acs_admissions acs
    ON a.hadm_id = acs.hadm_id
  INNER JOIN
    first_troponin ft
    ON a.hadm_id = ft.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
),
troponin_category AS (
  SELECT
    hadm_id,
    hospital_expire_flag,
    CASE
      WHEN troponin_value <= 0.01 THEN 'Normal/Minimal'
      WHEN troponin_value <= 0.039 THEN 'Borderline'
      WHEN troponin_value >= 0.04 THEN 'Elevated'
      ELSE 'Other'
    END AS troponin_group
  FROM
    eligible_patients
),
grouped_stats AS (
  SELECT
    troponin_group,
    COUNT(*) AS patient_count,
    SUM(hospital_expire_flag) AS deaths,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    troponin_category
  WHERE
    troponin_group IN ('Normal/Minimal', 'Borderline', 'Elevated')
  GROUP BY
    troponin_group
),
total_count AS (
  SELECT SUM(patient_count) AS total FROM grouped_stats
)
SELECT
  gs.troponin_group,
  gs.patient_count,
  ROUND(gs.patient_count * 100.0 / tc.total, 2) AS percentage,
  ROUND(gs.mortality_rate * 100, 2) AS mortality_rate_percent
FROM
  grouped_stats gs
CROSS JOIN
  total_count tc
ORDER BY
  CASE gs.troponin_group
    WHEN 'Normal/Minimal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;