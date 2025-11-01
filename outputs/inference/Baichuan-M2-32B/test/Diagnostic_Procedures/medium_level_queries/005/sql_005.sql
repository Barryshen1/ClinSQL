WITH patients_with_age AS (
  SELECT 
    subject_id,
    anchor_year - anchor_age AS birth_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
),
admissions_with_age AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    p.birth_year,
    EXTRACT(YEAR FROM a.admittime) - p.birth_year AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients_with_age p ON a.subject_id = p.subject_id
  WHERE EXTRACT(YEAR FROM a.admittime) - p.birth_year BETWEEN 49 AND 59
),
ischemic_stroke_diagnoses AS (
  SELECT 
    d.hadm_id,
    d.seq_num,
    d.icd_code,
    CASE 
      WHEN d.icd_code LIKE '433%' OR d.icd_code LIKE '434.5%' OR d.icd_code LIKE '436%' THEN 1
      ELSE 0 
    END AS is_ischemic_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
),
primary_diagnosis_per_admission AS (
  SELECT 
    hadm_id,
    icd_code AS primary_icd_code,
    seq_num AS primary_seq_num
  FROM (
    SELECT 
      hadm_id,
      icd_code,
      seq_num,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY seq_num ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  ) ranked
  WHERE rn = 1
),
admission_diagnosis_type AS (
  SELECT 
    hadm_id,
    stroke_diagnosis_type
  FROM (
    SELECT 
      a.hadm_id,
      CASE 
        WHEN p.primary_icd_code IN (SELECT icd_code FROM ischemic_stroke_diagnoses WHERE is_ischemic_stroke=1) THEN 'primary'
        WHEN EXISTS (
          SELECT 1 
          FROM ischemic_stroke_diagnoses d 
          WHERE d.hadm_id = a.hadm_id AND d.is_ischemic_stroke=1
        ) THEN 'secondary'
        ELSE NULL 
      END AS stroke_diagnosis_type
    FROM admissions_with_age a
    LEFT JOIN primary_diagnosis_per_admission p ON a.hadm_id = p.hadm_id
  )
  WHERE stroke_diagnosis_type IS NOT NULL
),
icu_stays_longest AS (
  SELECT 
    hadm_id,
    subject_id,
    los,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY los DESC) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
icu_stays_filtered AS (
  SELECT 
    hadm_id,
    los / 24.0 AS los_days
  FROM icu_stays_longest
  WHERE rn = 1
    AND los / 24.0 BETWEEN 1 AND 8
),
diagnostic_procedures AS (
  SELECT 
    p.hadm_id,
    COUNT(*) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE 
    LOWER(d.long_title) LIKE '%diagnostic%' OR 
    LOWER(d.long_title) LIKE '%imaging%' OR 
    LOWER(d.long_title) LIKE '%scan%' OR 
    LOWER(d.long_title) LIKE '%echo%' OR 
    LOWER(d.long_title) LIKE '%x-ray%' OR 
    LOWER(d.long_title) LIKE '%mri%' OR 
    LOWER(d.long_title) LIKE '%ct%' OR 
    LOWER(d.long_title) LIKE '%ultrasound%' OR 
    LOWER(d.long_title) LIKE '%angiogram%' OR 
    LOWER(d.long_title) LIKE '%biopsy%'
  GROUP BY p.hadm_id
),
combined AS (
  SELECT 
    a.hadm_id,
    a.age_at_admission,
    ad.stroke_diagnosis_type,
    i.los_days,
    COALESCE(dp.num_procedures, 0) AS num_procedures
  FROM admissions_with_age a
  JOIN admission_diagnosis_type ad ON a.hadm_id = ad.hadm_id
  JOIN icu_stays_filtered i ON a.hadm_id = i.hadm_id
  LEFT JOIN diagnostic_procedures dp ON a.hadm_id = dp.hadm_id
)
SELECT 
  CASE 
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
  END AS icu_stay_duration,
  stroke_diagnosis_type,
  AVG(num_procedures) AS mean_procedures,
  MIN(num_procedures) AS min_procedures,
  MAX(num_procedures) AS max_procedures
FROM combined
GROUP BY icu_stay_duration, stroke_diagnosis_type
ORDER BY icu_stay_duration, stroke_diagnosis_type;