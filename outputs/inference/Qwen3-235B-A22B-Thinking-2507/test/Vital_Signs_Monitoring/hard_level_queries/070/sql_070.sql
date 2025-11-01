WITH hhs_patients AS (
  SELECT 
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_version = 10
    AND d.icd_code IN ('E1101', 'E1301', 'E0801', 'E0901', 'E1001')
),

cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.los AS icu_los,
    a.hospital_expire_flag,
    -- Calculate age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  INNER JOIN hhs_patients h
    ON a.hadm_id = h.hadm_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) BETWEEN (p.anchor_year - p.anchor_age) + 78 
      AND (p.anchor_year - p.anchor_age) + 88
),

vital_signs_24h AS (
  SELECT 
    c.stay_id,
    ce.itemid,
    ce.valuenum
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid IN (220045, 225312, 220210)
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
),

cv_calculation AS (
  SELECT 
    stay_id,
    -- Calculate CV for each vital sign (with validation)
    SAFE_DIVIDE(STDDEV(CASE WHEN itemid = 220045 THEN valuenum END), 
                AVG(CASE WHEN itemid = 220045 THEN valuenum END)) AS cv_hr,
    SAFE_DIVIDE(STDDEV(CASE WHEN itemid = 225312 THEN valuenum END), 
                AVG(CASE WHEN itemid = 225312 THEN valuenum END)) AS cv_map,
    SAFE_DIVIDE(STDDEV(CASE WHEN itemid = 220210 THEN valuenum END), 
                AVG(CASE WHEN itemid = 220210 THEN valuenum END)) AS cv_rr
  FROM vital_signs_24h
  GROUP BY stay_id
  HAVING 
    COUNT(CASE WHEN itemid = 220045 THEN 1 END) >= 2 AND
    COUNT(CASE WHEN itemid = 225312 THEN 1 END) >= 2 AND
    COUNT(CASE WHEN itemid = 220210 THEN 1 END) >= 2
),

cohort_with_metrics AS (
  SELECT 
    c.*,
    -- CV sum as instability score
    (cv.cv_hr + cv.cv_map + cv.cv_rr) AS instability_score,
    -- Calculate quartile and decile across entire cohort
    NTILE(4) OVER (ORDER BY (cv.cv_hr + cv.cv_map + cv.cv_rr) DESC) AS quartile,
    NTILE(10) OVER (ORDER BY (cv.cv_hr + cv.cv_map + cv.cv_rr) DESC) AS decile
  FROM cohort c
  INNER JOIN cv_calculation cv
    ON c.stay_id = cv.stay_id
),

abnormal_vitals AS (
  SELECT 
    c.stay_id,
    COUNT(*) AS abnormal_vital_count
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid IN (220045, 225312, 220210)
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND (
      (ce.itemid = 220045 AND (ce.valuenum < 60 OR ce.valuenum > 100)) OR
      (ce.itemid = 225312 AND (ce.valuenum < 70 OR ce.valuenum > 100)) OR
      (ce.itemid = 220210 AND (ce.valuenum < 12 OR ce.valuenum > 20))
    )
  GROUP BY c.stay_id
)

SELECT 
  cwm.stay_id,
  cwm.instability_score,
  cwm.decile,
  COALESCE(av.abnormal_vital_count, 0) AS abnormal_vital_count,
  cwm.icu_los,
  cwm.hospital_expire_flag AS in_hospital_mortality
FROM cohort_with_metrics cwm
LEFT JOIN abnormal_vitals av
  ON cwm.stay_id = av.stay_id
WHERE cwm.quartile = 1
ORDER BY cwm.instability_score DESC;