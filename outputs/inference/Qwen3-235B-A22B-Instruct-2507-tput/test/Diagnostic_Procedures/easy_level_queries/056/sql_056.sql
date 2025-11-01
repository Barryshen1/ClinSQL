WITH patient_ages AS (
  SELECT
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
),
filtered_patients AS (
  SELECT subject_id
  FROM patient_ages
  WHERE gender = 'F'
    AND age_at_admission >= 43
    AND age_at_admission <= 53
),
mcs_procedures AS (
  SELECT
    di.itemid,
    di.label
  FROM
    `physionet-data.mimiciv_3_1_icu`.d_items di
  WHERE
    LOWER(di.label) LIKE '%iabp%'
    OR LOWER(di.label) LIKE '%ecmo%'
    OR LOWER(di.label) LIKE '%ventricular assist%'
),
patient_mcs_counts AS (
  SELECT
    fp.subject_id,
    COUNT(DISTINCT mcs.itemid) AS distinct_mcs_count
  FROM
    filtered_patients fp
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    fp.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays icu
  ON
    a.hadm_id = icu.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.procedureevents pe
  ON
    icu.stay_id = pe.stay_id
  INNER JOIN
    mcs_procedures mcs
  ON
    pe.itemid = mcs.itemid
  GROUP BY
    fp.subject_id
)
SELECT
  PERCENTILE_CONT(distinct_mcs_count, 0.25) OVER() AS percentile_25
FROM
  patient_mcs_counts
LIMIT 1;