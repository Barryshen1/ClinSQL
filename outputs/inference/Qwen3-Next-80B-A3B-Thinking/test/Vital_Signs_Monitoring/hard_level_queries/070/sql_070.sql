WITH hhs_patients AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hospital_expire_flag,
    i.los AS icu_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON i.hadm_id = d.hadm_id AND i.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 78 AND 88
    AND (dd.long_title LIKE '%hyperosmolar%' OR dd.long_title LIKE '%hyperglycemic state%')
),
vital_signs AS (
  SELECT 
    h.stay_id,
    c.itemid,
    AVG(c.valuenum) AS mean_val,
    STDDEV(c.valuenum) AS stddev_val
  FROM hhs_patients h
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON h.stay_id = c.stay_id
  WHERE 
    c.itemid IN (220045, 220052, 220210)
    AND c.charttime BETWEEN h.intime AND h.intime + INTERVAL '24' HOUR
    AND c.valuenum IS NOT NULL
  GROUP BY h.stay_id, c.itemid
),
cv_sum AS (
  SELECT 
    stay_id,
    SUM(stddev_val / NULLIF(mean_val, 0)) AS cv_sum
  FROM vital_signs
  GROUP BY stay_id
),
cv_quartiles AS (
  SELECT 
    stay_id,
    cv_sum,
    NTILE(4) OVER (ORDER BY cv_sum) AS quartile
  FROM cv_sum
),
abnormal_count AS (
  SELECT 
    c.stay_id,
    COUNT(*) AS abnormal_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN hhs_patients h ON c.stay_id = h.stay_id
  WHERE 
    c.itemid IN (220045, 220052, 220210)
    AND c.charttime BETWEEN h.intime AND h.intime + INTERVAL '24' HOUR
    AND c.valuenum IS NOT NULL
    AND (
      (c.itemid = 220045 AND (c.valuenum < 60 OR c.valuenum > 100)) OR
      (c.itemid = 220052 AND (c.valuenum < 70 OR c.valuenum > 110)) OR
      (c.itemid = 220210 AND (c.valuenum < 12 OR c.valuenum > 20))
    )
  GROUP BY c.stay_id
),
decile AS (
  SELECT 
    stay_id,
    NTILE(10) OVER (ORDER BY cv_sum) AS decile
  FROM cv_sum
)
SELECT 
  c.stay_id,
  c.cv_sum AS stay_instability_score,
  d.decile,
  a.abnormal_count,
  h.icu_los,
  h.hospital_expire_flag
FROM cv_quartiles c
JOIN hhs_patients h ON c.stay_id = h.stay_id
LEFT JOIN abnormal_count a ON c.stay_id = a.stay_id
JOIN decile d ON c.stay_id = d.stay_id
WHERE c.quartile = 4;