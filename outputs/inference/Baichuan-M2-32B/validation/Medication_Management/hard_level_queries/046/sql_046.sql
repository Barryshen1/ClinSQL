WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_year,
    p.anchor_age,
    TIMESTAMP_DIFF(a.admittime, DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR), YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
multi_trauma AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS trauma_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code BETWEEN '800' AND '994') OR 
    (icd_version = 10 AND icd_code BETWEEN 'S00' AND 'T98')
  GROUP BY hadm_id
  HAVING trauma_count >= 2
),
med_complexity AS (
  SELECT
    p.hadm_id,
    COUNT(DISTINCT p.formulary_drug_cd) AS med_complexity
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.hadm_id = a.hadm_id
  WHERE p.starttime BETWEEN a.admittime AND a.admittime + INTERVAL 7 DAY
  GROUP BY p.hadm_id
),
admissions_with_metrics AS (
  SELECT
    pa.hadm_id,
    pa.subject_id,
    pa.admittime,
    pa.dischtime,
    pa.hospital_expire_flag,
    pa.age_at_admission,
    m.trauma_count,
    COALESCE(mc.med_complexity, 0) AS med_complexity
  FROM patient_admissions pa
  INNER JOIN multi_trauma m
    ON pa.hadm_id = m.hadm_id
  LEFT JOIN med_complexity mc
    ON pa.hadm_id = mc.hadm_id
  WHERE pa.age_at_admission BETWEEN 45 AND 55
),
readmission_flags AS (
  SELECT
    a1.hadm_id,
    a1.subject_id,
    a1.dischtime,
    (SELECT MIN(admittime) 
     FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
     WHERE a2.subject_id = a1.subject_id
       AND a2.admittime > a1.dischtime) AS next_admit
  FROM admissions_with_metrics a1
),
admissions_with_readmission AS (
  SELECT
    a.*,
    CASE 
      WHEN r.next_admit IS NOT NULL AND r.next_admit <= a.dischtime + INTERVAL 30 DAY THEN 1
      ELSE 0 
    END AS readmission_30d
  FROM admissions_with_metrics a
  LEFT JOIN readmission_flags r
    ON a.hadm_id = r.hadm_id
),
tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_complexity) AS tertile
  FROM admissions_with_readmission
)
SELECT
  tertile,
  COUNT(*) AS admissions,
  AVG(med_complexity) AS mean_score,
  MIN(med_complexity) AS min_score,
  MAX(med_complexity) AS max_score,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS mean_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percent,
  AVG(CAST(readmission_30d AS FLOAT64)) * 100 AS readmission_percent
FROM tertiles
GROUP BY tertile
ORDER BY tertile;