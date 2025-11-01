WITH hepatic_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND LOWER(did.long_title) LIKE '%hepatic%failure%'
),

icu_stays_with_first_72h AS (
  SELECT i.stay_id, i.hadm_id, i.intime, i.los,
         COUNT(DISTINCT pr.drug) AS med_complexity_score
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN hepatic_patients hp ON i.hadm_id = hp.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON i.hadm_id = pr.hadm_id 
    AND pr.starttime >= i.intime 
    AND pr.starttime < TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY i.stay_id, i.hadm_id, i.intime, i.los
),

readmission_flag AS (
  SELECT a1.subject_id, a1.hadm_id,
         CASE WHEN EXISTS (
           SELECT 1 
           FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2 
           WHERE a2.subject_id = a1.subject_id 
             AND a2.admittime > a1.dischtime 
             AND a2.admittime <= TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
         ) THEN 1 ELSE 0 END AS readmission_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
  INNER JOIN hepatic_patients hp ON a1.hadm_id = hp.hadm_id
),

final_cohort AS (
  SELECT 
    i.stay_id,
    i.med_complexity_score,
    i.los,
    hp.hospital_expire_flag,
    COALESCE(r.readmission_30d, 0) AS readmission_30d,
    NTILE(5) OVER (ORDER BY i.med_complexity_score) AS quintile
  FROM icu_stays_with_first_72h i
  INNER JOIN hepatic_patients hp ON i.hadm_id = hp.hadm_id
  LEFT JOIN readmission_flag r ON i.hadm_id = r.hadm_id
)

SELECT 
  quintile,
  COUNT(*) AS n,
  MIN(med_complexity_score) AS min_score,
  MAX(med_complexity_score) AS max_score,
  AVG(med_complexity_score) AS mean_score,
  AVG(los) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct,
  AVG(readmission_30d) * 100 AS readmission_30d_pct
FROM final_cohort
GROUP BY quintile
ORDER BY quintile;