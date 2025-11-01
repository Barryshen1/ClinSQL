WITH first_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE a.hadm_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
),
pneumonia_hadm AS (
  SELECT 
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%pneumonia%'
  GROUP BY d.hadm_id
),
filtered_patients AS (
  SELECT 
    fa.subject_id,
    fa.hadm_id
  FROM first_admissions fa
  INNER JOIN pneumonia_hadm ph
    ON fa.hadm_id = ph.hadm_id
  WHERE fa.gender = 'M'
    AND fa.age_at_admission BETWEEN 51 AND 61
),
icu_los AS (
  SELECT 
    fp.hadm_id,
    COALESCE(SUM(i.los), 0) AS total_los
  FROM filtered_patients fp
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON fp.hadm_id = i.hadm_id
  GROUP BY fp.hadm_id
)
SELECT 
  APPROX_QUANTILES(total_los, 100)[OFFSET(25)] AS percentile_25
FROM icu_los;