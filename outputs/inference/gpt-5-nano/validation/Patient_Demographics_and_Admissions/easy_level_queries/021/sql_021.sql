WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    -- age at admission: anchor_age + (year(admittime) - anchor_year)
    AND (CAST(p.anchor_age AS INT64)
         + (EXTRACT(YEAR FROM a.admittime) - CAST(p.anchor_year AS INT64))) BETWEEN 83 AND 93
    -- pneumonia (case-insensitive)
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
),
first_per_subject AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM cohort
),
first_adm AS (
  SELECT subject_id, hadm_id
  FROM first_per_subject
  WHERE rn = 1
),
death_flags AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    CASE
      WHEN h.hospital_expire_flag = 1 OR h.deathtime IS NOT NULL THEN 1
      ELSE 0
    END AS is_death
  FROM first_adm fa
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS h
    ON fa.hadm_id = h.hadm_id
)
SELECT
  100.0 * SUM(is_death) / COUNT(*) AS in_hospital_mortality_pct
FROM death_flags;