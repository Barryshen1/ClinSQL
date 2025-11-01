WITH eligible AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.insurance,
    a.admission_type,
    a.admission_location,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE
    (LOWER(a.admission_type) LIKE '%emergency%' OR LOWER(a.admission_location) LIKE '%ed%')
    AND LOWER(a.insurance) LIKE '%medicare%'
    AND di.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%diabetic ketoacidosis%'
),
ages AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    insurance,
    admission_type,
    admission_location,
    anchor_age,
    anchor_year,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admit
  FROM eligible
)
SELECT COUNT(*) AS index_admissions_count
FROM (
  SELECT
     subject_id,
     hadm_id,
     admittime,
     age_at_admit,
     ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM ages
  WHERE age_at_admit BETWEEN 43 AND 53
) t
WHERE rn = 1;