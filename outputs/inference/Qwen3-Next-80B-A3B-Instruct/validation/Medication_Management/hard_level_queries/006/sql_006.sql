WITH surgical_icu_stays AS (
  SELECT DISTINCT
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag,
    a.dischtime
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.services s
    ON i.hadm_id = s.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND s.curr_service = 'SURG'
    AND s.transfertime >= DATETIME_SUB(i.intime, INTERVAL 24 HOUR)
    AND s.transfertime <= DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
),
medication_complexity AS (
  SELECT
    s.stay_id,
    COUNT(DISTINCT di.label) AS med_complexity
  FROM surgical_icu_stays s
  INNER JOIN physionet-data.mimiciv_3_1_icu.inputevents ie
    ON s.stay_id = ie.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ie.itemid = di.itemid
  WHERE ie.starttime >= s.intime
    AND ie.starttime <= DATETIME_ADD(s.intime, INTERVAL 72 HOUR)
    AND di.label IS NOT NULL
  GROUP BY s.stay_id
),
readmission_30d AS (
  SELECT
    a1.subject_id,
    a1.hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmit_30d
  FROM physionet-data.mimiciv_3_1_hosp.admissions a1
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.admissions a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= DATETIME_ADD(a1.dischtime, INTERVAL 30 DAY)
  WHERE a1.hadm_id IS NOT NULL
),
final_data AS (
  SELECT
    s.stay_id,
    s.hospital_expire_flag,
    s.los,
    COALESCE(r.readmit_30d, 0) AS readmit_30d,
    mc.med_complexity,
    NTILE(5) OVER (ORDER BY mc.med_complexity) AS quintile
  FROM surgical_icu_stays s
  LEFT JOIN medication_complexity mc ON s.stay_id = mc.stay_id
  LEFT JOIN readmission_30d r ON s.hadm_id = r.hadm_id
  WHERE mc.med_complexity IS NOT NULL
)
SELECT
  quintile,
  COUNT(*) AS n_patients,
  AVG(los) AS avg_los,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
  AVG(readmit_30d) AS thirty_day_readmission_rate
FROM final_data
GROUP BY quintile
ORDER BY quintile;