WITH patients_adm AS (
  SELECT 
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - 2008 AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
),
trauma_count AS (
  SELECT 
    pa.*,
    COUNT(DISTINCT CASE 
      WHEN (
        (di.icd_version = 9 AND CAST(LEFT(di.icd_code, 3) AS INT64) BETWEEN 800 AND 959)
        OR 
        (di.icd_version = 10 AND LEFT(di.icd_code, 1) IN ('S', 'T'))
      ) THEN di.icd_code 
    END) AS num_trauma
  FROM patients_adm pa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON pa.hadm_id = di.hadm_id
  GROUP BY 
    pa.subject_id, pa.gender, pa.hadm_id, pa.admittime, pa.dischtime, 
    pa.deathtime, pa.hospital_expire_flag, pa.age_at_adm
),
cohort AS (
  SELECT *
  FROM trauma_count
  WHERE gender = 'F'
    AND age_at_adm BETWEEN 45 AND 55
    AND num_trauma >= 2
),
meds AS (
  SELECT 
    c.*,
    COUNT(DISTINCT pres.drug) AS med_complexity_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres 
    ON c.hadm_id = pres.hadm_id
    AND pres.drug IS NOT NULL
    AND pres.starttime >= c.admittime
    AND pres.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY 
    c.subject_id, c.gender, c.hadm_id, c.admittime, c.dischtime, 
    c.deathtime, c.hospital_expire_flag, c.age_at_adm, c.num_trauma
),
with_tertile AS (
  SELECT *,
    NTILE(3) OVER (ORDER BY med_complexity_score ASC) AS tertile
  FROM meds
),
with_readmission AS (
  SELECT *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 0
      ELSE 
        CASE WHEN EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
          WHERE a2.subject_id = with_tertile.subject_id
            AND a2.hadm_id != with_tertile.hadm_id
            AND a2.admittime > with_tertile.dischtime
            AND a2.admittime <= TIMESTAMP_ADD(with_tertile.dischtime, INTERVAL 30 DAY)
        ) THEN 1 ELSE 0 END
    END AS has_readmission
  FROM with_tertile
)
SELECT 
  tertile,
  COUNT(*) AS num_admissions,
  AVG(med_complexity_score) AS mean_score,
  MIN(med_complexity_score) AS min_score,
  MAX(med_complexity_score) AS max_score,
  AVG(DATE_DIFF(dischtime, admittime, DAY)) AS mean_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct,
  SAFE_DIVIDE(
    SUM(CAST(CASE WHEN hospital_expire_flag = 0 AND has_readmission = 1 THEN 1 ELSE 0 END AS FLOAT64)),
    SUM(CAST(CASE WHEN hospital_expire_flag = 0 THEN 1 ELSE 0 END AS FLOAT64))
  ) * 100 AS readmission_30d_pct
FROM with_readmission
GROUP BY tertile
ORDER BY tertile;