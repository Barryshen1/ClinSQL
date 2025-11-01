WITH first_icu_stays AS (
  SELECT 
    stay.*,
    ROW_NUMBER() OVER (PARTITION BY stay.subject_id ORDER BY stay.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` stay
),
filtered_icu AS (
  SELECT 
    stay.subject_id,
    stay.hadm_id,
    stay.stay_id,
    stay.intime,
    stay.los,
    p.anchor_age + (EXTRACT(YEAR FROM stay.intime) - p.anchor_year) AS age_at_icu
  FROM first_icu_stays stay
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON stay.subject_id = p.subject_id
  WHERE stay.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM stay.intime) - p.anchor_year) BETWEEN 37 AND 47
),
with_pneumonia AS (
  SELECT 
    f.*
  FROM filtered_icu f
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.hadm_id = f.hadm_id
      AND (
        (d.icd_version = 9 AND d.icd_code >= '480' AND d.icd_code < '487')
        OR 
        (d.icd_version = 10 AND d.icd_code LIKE 'J1[2-8]%')
      )
  )
),
procedures_count AS (
  SELECT 
    w.*,
    a.hospital_expire_flag,
    COUNT(DISTINCT p.itemid) AS proc_count
  FROM with_pneumonia w
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON w.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON w.stay_id = p.stay_id
    AND p.starttime >= w.intime
    AND p.starttime <= w.intime + INTERVAL 48 HOUR
  GROUP BY w.subject_id, w.hadm_id, w.stay_id, w.intime, w.los, w.age_at_icu, a.hospital_expire_flag
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM procedures_count
)
SELECT 
  quintile,
  AVG(proc_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) AS hospital_mortality_rate
FROM quintiles
GROUP BY quintile
ORDER BY quintile;