WITH acs_diagnoses AS (
  SELECT 
    di.subject_id,
    di.hadm_id,
    di.seq_num,
    CASE WHEN di.seq_num = 1 THEN 'primary' ELSE 'secondary' END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON di.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 77 AND 87
    AND (
      LOWER(dicd.long_title) LIKE '%acute coronary syndrome%'
      OR LOWER(dicd.long_title) LIKE '%myocardial infarction%'
      OR LOWER(dicd.long_title) LIKE '%unstable angina%'
      OR LOWER(dicd.long_title) LIKE '%acute myocardial infarction%'
      OR LOWER(dicd.long_title) LIKE '%coronary ischemia%'
    )
),
icu_stays_with_duration AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.los,
    CASE 
      WHEN i.los BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN i.los BETWEEN 5 AND 8 THEN '5-8 days'
    END AS stay_duration_bin
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  WHERE i.los BETWEEN 1 AND 8
),
imaging_events AS (
  SELECT 
    ce.stay_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.linksto = 'chartevents'
    AND (
      LOWER(di.label) LIKE '%ct%'
      OR LOWER(di.label) LIKE '%radiograph%'
      OR LOWER(di.label) LIKE '%x-ray%'
      OR LOWER(di.label) LIKE '%imaging%'
      OR LOWER(di.label) LIKE '%radiology%'
      OR LOWER(di.label) LIKE '%fluoroscopy%'
    )
  GROUP BY ce.stay_id

  UNION ALL

  SELECT 
    pe.stay_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE di.linksto = 'procedureevents'
    AND (
      LOWER(di.label) LIKE '%ct%'
      OR LOWER(di.label) LIKE '%radiograph%'
      OR LOWER(di.label) LIKE '%x-ray%'
      OR LOWER(di.label) LIKE '%imaging%'
      OR LOWER(di.label) LIKE '%radiology%'
      OR LOWER(di.label) LIKE '%fluoroscopy%'
    )
  GROUP BY pe.stay_id
),
imaging_counts_per_stay AS (
  SELECT 
    stay_id,
    SUM(imaging_count) AS total_imaging_count
  FROM imaging_events
  GROUP BY stay_id
)
SELECT 
  isd.stay_duration_bin,
  ad.diagnosis_type,
  AVG(icc.total_imaging_count) AS mean_imaging_count,
  MIN(icc.total_imaging_count) AS min_imaging_count,
  MAX(icc.total_imaging_count) AS max_imaging_count
FROM acs_diagnoses ad
INNER JOIN icu_stays_with_duration isd
  ON ad.subject_id = isd.subject_id AND ad.hadm_id = isd.hadm_id
LEFT JOIN imaging_counts_per_stay icc
  ON isd.stay_id = icc.stay_id
WHERE isd.stay_duration_bin IS NOT NULL
GROUP BY isd.stay_duration_bin, ad.diagnosis_type
ORDER BY isd.stay_duration_bin, ad.diagnosis_type;