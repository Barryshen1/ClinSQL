WITH hf_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.gender,
    CASE
      WHEN p.anchor_age IS NOT NULL AND p.anchor_year IS NOT NULL THEN
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
      ELSE NULL
    END AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  WHERE di.seq_num = 1
    AND (
      (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
      OR (di.icd_version = 9 AND di.icd_code LIKE '428%')
    )
    AND p.gender = 'F'
)

SELECT
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0), 2) AS avg_hospital_los_days
FROM hf_admissions
WHERE age_at_adm BETWEEN 61 AND 71
  AND dischtime IS NOT NULL;