WITH eligible_patients AS (
  SELECT
    subject_id,
    anchor_year,
    anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
),
admissions_with_los AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN eligible_patients p ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL
),
primary_dka_hhs_admissions AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE d.seq_num = 1
    AND (dd.long_title LIKE '%Diabetic Ketoacidosis%'
         OR dd.long_title LIKE '%Hyperosmolar Hyperglycemic State%')
),
final_admissions AS (
  SELECT
    awl.los_days
  FROM admissions_with_los awl
  INNER JOIN primary_dka_hhs_admissions pda
    ON awl.subject_id = pda.subject_id AND awl.hadm_id = pda.hadm_id
  WHERE awl.age_at_admission BETWEEN 73 AND 83
)
SELECT
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los_days) AS p25_los
FROM final_admissions;