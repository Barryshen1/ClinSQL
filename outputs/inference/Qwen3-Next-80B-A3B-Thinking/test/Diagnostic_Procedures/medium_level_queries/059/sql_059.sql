WITH admissions_with_age AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
),
hf_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.gender,
    a.age_at_admission,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
        WHERE di.hadm_id = a.hadm_id
          AND d.long_title LIKE '%heart failure%'
          AND di.seq_num = 1
      ) THEN 'primary'
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
        WHERE di.hadm_id = a.hadm_id
          AND d.long_title LIKE '%heart failure%'
          AND di.seq_num > 1
      ) THEN 'secondary'
      ELSE NULL
    END AS hf_type
  FROM admissions_with_age a
  WHERE a.gender = 'M'
    AND a.age_at_admission BETWEEN 67 AND 77
),
hosp_imaging AS (
  SELECT
    hadm_id,
    COUNT(*) AS hosp_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%radiology%'
     OR LOWER(d.long_title) LIKE '%imaging%'
     OR LOWER(d.long_title) LIKE '%ct%'
     OR LOWER(d.long_title) LIKE '%mri%'
     OR LOWER(d.long_title) LIKE '%x-ray%'
     OR LOWER(d.long_title) LIKE '%ultrasound%'
  GROUP BY hadm_id
),
icu_imaging AS (
  SELECT
    hadm_id,
    COUNT(*) AS icu_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON pe.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%ct%'
     OR LOWER(d.label) LIKE '%mri%'
     OR LOWER(d.label) LIKE '%x-ray%'
     OR LOWER(d.label) LIKE '%ultrasound%'
     OR LOWER(d.label) LIKE '%nuclear%'
  GROUP BY hadm_id
),
imaging_counts AS (
  SELECT
    a.hadm_id,
    COALESCE(h.hosp_count, 0) + COALESCE(i.icu_count, 0) AS total_imaging,
    a.hf_type
  FROM hf_admissions a
  LEFT JOIN hosp_imaging h ON a.hadm_id = h.hadm_id
  LEFT JOIN icu_imaging i ON a.hadm_id = i.hadm_id
  WHERE a.hf_type IS NOT NULL
),
los_categories AS (
  SELECT
    ic.hadm_id,
    ic.total_imaging,
    ic.hf_type,
    CASE
      WHEN EXTRACT(DAY FROM (a.dischtime - a.admittime)) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN EXTRACT(DAY FROM (a.dischtime - a.admittime)) BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE NULL
    END AS los_category
  FROM imaging_counts ic
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ic.hadm_id = a.hadm_id
  WHERE EXTRACT(DAY FROM (a.dischtime - a.admittime)) BETWEEN 1 AND 7
)
SELECT
  los_category,
  hf_type,
  PERCENTILE_CONT(total_imaging, 0.25) WITHIN GROUP (ORDER BY total_imaging) AS p25,
  PERCENTILE_CONT(total_imaging, 0.5) WITHIN GROUP (ORDER BY total_imaging) AS p50,
  PERCENTILE_CONT(total_imaging, 0.75) WITHIN GROUP (ORDER BY total_imaging) AS p75
FROM los_categories
WHERE los_category IS NOT NULL
GROUP BY los_category, hf_type;