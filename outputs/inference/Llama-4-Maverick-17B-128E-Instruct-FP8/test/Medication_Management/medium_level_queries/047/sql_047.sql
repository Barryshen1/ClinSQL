WITH cohort AS (
  SELECT p.subject_id, a.hadm_id, icu.stay_id, 
         p.anchor_age, p.gender, 
         icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 40 AND 50
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code LIKE 'E10%' OR icd_code LIKE 'E11%'  -- Diabetes
    )
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code LIKE 'I50%'  -- Heart Failure
    )
),
meds AS (
  SELECT c.subject_id, c.stay_id, c.intime, c.outtime,
         pr.drug, pr.starttime, pr.stoptime
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON c.hadm_id = pr.hadm_id
  WHERE pr.drug_type = 'MAIN RX'
    AND (
      LOWER(pr.drug) LIKE '%metformin%' OR 
      LOWER(pr.drug) LIKE '%glimepiride%' OR 
      LOWER(pr.drug) LIKE '%insulin%' OR  -- Antidiabetic
      LOWER(pr.drug) LIKE '%metoprolol%' OR 
      LOWER(pr.drug) LIKE '%propranolol%' OR 
      LOWER(pr.drug) LIKE '%atenolol%' OR  -- Beta-blocker
      LOWER(pr.drug) LIKE '%lisinopril%' OR 
      LOWER(pr.drug) LIKE '%enalapril%' OR 
      LOWER(pr.drug) LIKE '%losartan%' OR  -- ACEi/ARB
      LOWER(pr.drug) LIKE '%furosemide%' OR 
      LOWER(pr.drug) LIKE '%bumetanide%'  -- Loop diuretic
    )
),
med_timing AS (
  SELECT subject_id, stay_id, intime, outtime, drug,
         CASE 
           WHEN starttime <= TIMESTAMP_ADD(intime, INTERVAL 24 HOUR) THEN 'First 24h'
           ELSE 'Not First 24h'
         END AS first_24h,
         CASE 
           WHEN stoptime >= TIMESTAMP_SUB(outtime, INTERVAL 24 HOUR) THEN 'Last 24h'
           ELSE 'Not Last 24h'
         END AS last_24h,
         CASE 
           WHEN starttime <= intime AND stoptime >= outtime THEN 'Continued'
           WHEN starttime > intime AND starttime <= outtime THEN 'Initiated'
           WHEN stoptime < outtime THEN 'Discontinued'
           ELSE 'Other'
         END AS med_status
  FROM meds
)
SELECT 
  drug,
  COUNT(DISTINCT subject_id) AS total_patients,
  SUM(CASE WHEN first_24h = 'First 24h' THEN 1 ELSE 0 END) / COUNT(DISTINCT subject_id) AS perc_first_24h,
  SUM(CASE WHEN last_24h = 'Last 24h' THEN 1 ELSE 0 END) / COUNT(DISTINCT subject_id) AS perc_last_24h,
  SUM(CASE WHEN med_status = 'Continued' THEN 1 ELSE 0 END) AS count_continued,
  SUM(CASE WHEN med_status = 'Initiated' AND first_24h = 'Not First 24h' THEN 1 ELSE 0 END) AS count_initiated_late,
  SUM(CASE WHEN med_status = 'Discontinued' THEN 1 ELSE 0 END) AS count_discontinued
FROM med_timing
GROUP BY drug;