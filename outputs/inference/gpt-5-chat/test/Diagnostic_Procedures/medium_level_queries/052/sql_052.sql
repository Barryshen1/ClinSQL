WITH patient_admit AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    -- approximate age at admission
    pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year AS admit_age,
    adm.admission_type,
    adm.admittime,
    adm.dischtime,
    DATE_DIFF(DATE(adm.dischtime), DATE(adm.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
),
multi_trauma_admits AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.gender,
    pa.admit_age,
    pa.admission_type,
    pa.admittime,
    pa.dischtime,
    pa.los_days
  FROM patient_admit pa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON pa.subject_id = di.subject_id
    AND pa.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE pa.gender = 'F'
    AND pa.admit_age BETWEEN 73 AND 83
    AND (
      UPPER(dd.long_title) LIKE '%TRAUMA%'
      OR UPPER(dd.long_title) LIKE '%INJURY%'
    )
  GROUP BY pa.subject_id, pa.hadm_id, pa.gender, pa.admit_age, pa.admission_type, pa.admittime, pa.dischtime, pa.los_days
  HAVING COUNT(DISTINCT di.icd_code) > 1
),
ultrasound_counts AS (
  SELECT
    mt.subject_id,
    mt.hadm_id,
    COUNT(p.icd_code) AS ultrasound_count
  FROM multi_trauma_admits mt
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON mt.subject_id = p.subject_id
    AND mt.hadm_id = p.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE dp.long_title LIKE '%Ultrasound%' 
     OR dp.long_title LIKE '%Echocardiography%'
  GROUP BY mt.subject_id, mt.hadm_id
),
admit_with_ultrasound AS (
  SELECT
    mt.subject_id,
    mt.hadm_id,
    mt.los_days,
    CASE 
      WHEN mt.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN mt.los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS los_group,
    CASE 
      WHEN UPPER(mt.admission_type) LIKE '%ELECTIVE%' THEN 'Elective'
      WHEN UPPER(mt.admission_type) LIKE '%EMERGENCY%' THEN 'ED'
      ELSE 'Other'
    END AS admit_type_group,
    COALESCE(uc.ultrasound_count, 0) AS ultrasound_count
  FROM multi_trauma_admits mt
  LEFT JOIN ultrasound_counts uc
    ON mt.subject_id = uc.subject_id
    AND mt.hadm_id = uc.hadm_id
)
SELECT
  los_group,
  admit_type_group,
  COUNT(DISTINCT hadm_id) AS num_admissions,
  ROUND(AVG(ultrasound_count),2) AS mean_ultrasounds,
  MIN(ultrasound_count) AS min_ultrasounds,
  MAX(ultrasound_count) AS max_ultrasounds
FROM admit_with_ultrasound
WHERE los_group IS NOT NULL
  AND admit_type_group IN ('ED','Elective')
GROUP BY los_group, admit_type_group
ORDER BY los_group, admit_type_group;