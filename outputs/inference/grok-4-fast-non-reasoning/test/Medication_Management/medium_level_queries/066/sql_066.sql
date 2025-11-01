WITH qualifying_admissions AS (
  -- Select qualifying admissions: males 58-68, LOS >=72h, with T2DM and HF diagnoses (any position)
  SELECT DISTINCT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
        ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
      WHERE d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
        AND LOWER(icd.long_title) LIKE '%diabetes mellitus type 2%'  -- T2DM (any seq_num)
    )
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd2
        ON d2.icd_code = icd2.icd_code AND d2.icd_version = icd2.icd_version
      WHERE d2.subject_id = a.subject_id AND d2.hadm_id = a.hadm_id
        AND LOWER(icd2.long_title) LIKE '%heart failure%'  -- HF (any seq_num)
    )
),

glp1_first_72h AS (
  -- Admissions with GLP-1 start in first 72h
  SELECT DISTINCT qa.hadm_id
  FROM qualifying_admissions qa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON pres.hadm_id = qa.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` pharm
    ON pres.pharmacy_id = pharm.pharmacy_id
  WHERE pharm.medication LIKE '%semaglutide%' OR pharm.medication LIKE '%liraglutide%'
     OR pharm.medication LIKE '%exenatide%' OR pharm.medication LIKE '%dulaglutide%'
     OR pharm.medication LIKE '%albiglutide%' OR pharm.medication LIKE '%lixisenatide%'
    AND pres.starttime >= qa.admittime
    AND pres.starttime < TIMESTAMP_ADD(qa.admittime, INTERVAL 72 HOUR)
),

glp1_final_12h AS (
  -- Admissions with GLP-1 start in final 12h
  SELECT DISTINCT qa.hadm_id
  FROM qualifying_admissions qa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON pres.hadm_id = qa.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` pharm
    ON pres.pharmacy_id = pharm.pharmacy_id
  WHERE pharm.medication LIKE '%semaglutide%' OR pharm.medication LIKE '%liraglutide%'
     OR pharm.medication LIKE '%exenatide%' OR pharm.medication LIKE '%dulaglutide%'
     OR pharm.medication LIKE '%albiglutide%' OR pharm.medication LIKE '%lixisenatide%'
    AND pres.starttime >= TIMESTAMP_SUB(qa.dischtime, INTERVAL 12 HOUR)
    AND pres.starttime < qa.dischtime
)

-- Aggregate metrics
SELECT
  COUNT(DISTINCT qa.hadm_id) AS total_qualifying_admissions,
  COUNT(DISTINCT f72.hadm_id) AS glp1_first_72h_count,
  SAFE_DIVIDE(COUNT(DISTINCT f72.hadm_id), COUNT(DISTINCT qa.hadm_id)) * 100 AS first_72h_percentage,
  COUNT(DISTINCT f12.hadm_id) AS glp1_final_12h_count,
  SAFE_DIVIDE(COUNT(DISTINCT f12.hadm_id), COUNT(DISTINCT qa.hadm_id)) * 100 AS final_12h_percentage,
  ABS(
    SAFE_DIVIDE(COUNT(DISTINCT f72.hadm_id), COUNT(DISTINCT qa.hadm_id)) * 100 -
    SAFE_DIVIDE(COUNT(DISTINCT f12.hadm_id), COUNT(DISTINCT qa.hadm_id)) * 100
  ) AS absolute_difference_pp
FROM qualifying_admissions qa
LEFT JOIN glp1_first_72h f72 ON qa.hadm_id = f72.hadm_id
LEFT JOIN glp1_final_12h f12 ON qa.hadm_id = f12.hadm_id;