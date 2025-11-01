WITH patients_admissions AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_adm
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
),
trauma_admissions AS (
  SELECT 
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND SAFE_CAST(SUBSTR(icd_code, 1, 3) AS INT64) BETWEEN 800 AND 959)
    OR (icd_version = 10 AND (icd_code LIKE 'S%' OR icd_code LIKE 'T%'))
  GROUP BY hadm_id
  HAVING COUNT(DISTINCT icd_code) >= 2
),
cohort AS (
  SELECT 
    pa.subject_id, 
    pa.hadm_id, 
    pa.admittime, 
    pa.dischtime,
    pa.hospital_expire_flag,
    pa.age_adm
  FROM patients_admissions pa
  INNER JOIN trauma_admissions ta
    ON pa.hadm_id = ta.hadm_id
  WHERE pa.age_adm BETWEEN 45 AND 55
),
meds AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_complexity_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime <= DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
    AND (pr.stoptime >= c.admittime OR pr.stoptime IS NULL)
  GROUP BY c.hadm_id
),
with_tertile AS (
  SELECT 
    c.*,
    m.med_complexity_score,
    NTILE(3) OVER (ORDER BY m.med_complexity_score) AS tertile
  FROM cohort c
  INNER JOIN meds m
    ON c.hadm_id = m.hadm_id
),
readmission_flags AS (
  SELECT 
    wt.hadm_id,
    CASE 
      WHEN wt.hospital_expire_flag = 1 THEN NULL
      WHEN MIN(a.admittime) IS NOT NULL THEN 1
      ELSE 0 
    END AS readmission_flag
  FROM with_tertile wt
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON wt.subject_id = a.subject_id
    AND a.admittime > wt.dischtime
    AND a.admittime <= DATETIME_ADD(wt.dischtime, INTERVAL 30 DAY)
  GROUP BY wt.hadm_id, wt.hospital_expire_flag
),
final_data AS (
  SELECT 
    wt.*,
    rf.readmission_flag,
    DATETIME_DIFF(wt.dischtime, wt.admittime, DAY) AS los_days
  FROM with_tertile wt
  LEFT JOIN readmission_flags rf
    ON wt.hadm_id = rf.hadm_id
)
SELECT 
  tertile,
  COUNT(hadm_id) AS admissions,
  AVG(med_complexity_score) AS mean_score,
  MIN(med_complexity_score) AS min_score,
  MAX(med_complexity_score) AS max_score,
  AVG(los_days) AS mean_los,
  100.0 * AVG(hospital_expire_flag) AS mortality_pct,
  100.0 * AVG(IF(hospital_expire_flag = 0, readmission_flag, NULL)) AS readmission_pct
FROM final_data
GROUP BY tertile
ORDER BY tertile;