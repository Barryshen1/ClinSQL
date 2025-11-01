WITH cabg_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%coronary artery bypass%'
),
cabg_admissions AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN cabg_codes c
    ON p.icd_code = c.icd_code AND p.icd_version = c.icd_version
),
first_cabg_admissions AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    a.admittime,
    pat.anchor_year,
    pat.anchor_age,
    pat.gender
  FROM cabg_admissions ca
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ca.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ca.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ca.subject_id ORDER BY a.admittime) = 1
),
eligible_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission
  FROM first_cabg_admissions
  WHERE anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) BETWEEN 74 AND 84
),
icu_los_per_admission AS (
  SELECT
    e.hadm_id,
    COALESCE(SUM(i.los), 0) AS total_icu_los
  FROM eligible_admissions e
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON e.hadm_id = i.hadm_id
  GROUP BY e.hadm_id
)
SELECT
  ROUND(AVG(total_icu_los), 4) AS mean_icu_los_days
FROM icu_los_per_admission;