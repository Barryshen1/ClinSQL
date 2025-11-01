WITH icu_first AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime, 
    ie.outtime,
    ie.los AS icu_los,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY ie.hadm_id ORDER BY ie.intime) AS stay_seq
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ie.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
), 
cohort AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id,
    i.intime, 
    i.outtime,
    i.icu_los,
    i.anchor_age,
    i.gender,
    i.hospital_expire_flag,
    MAX(
      CASE 
        WHEN d.icd_version = 9 AND d.icd_code IN ('25020','25021','25022','25023') THEN 1
        WHEN d.icd_version = 10 AND d.icd_code IN ('E0800','E0801','E1100','E1101','E1300','E1301','E1400','E1401') THEN 1
        ELSE 0 
      END
    ) AS hhs_flag
  FROM icu_first i
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON i.hadm_id = d.hadm_id
  WHERE i.stay_seq = 1
  GROUP BY i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime, i.icu_los, i.anchor_age, i.gender, i.hospital_expire_flag
),
vitals AS (
  SELECT 
    c.stay_id,
    ce.charttime,
    ce.itemid,
    ce.valuenum,
    CASE 
      WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5/9  -- Convert F to C
      WHEN ce.itemid = 223762 THEN ce.valuenum
      ELSE NULL 
    END AS temp_c
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  WHERE ce.itemid IN (220045, 220179, 225309, 220210, 223761, 223762, 220277)
    AND ce.valuenum IS NOT NULL
),
vitals_agg AS (
  SELECT 
    stay_id,
    MIN(CASE WHEN itemid = 220045 THEN valuenum END) AS hr_min,
    MAX(CASE WHEN itemid = 220045 THEN valuenum END) AS hr_max,
    MIN(CASE WHEN itemid IN (220179, 225309) THEN valuenum END) AS sbp_min,
    MIN(CASE WHEN itemid = 220210 THEN valuenum END) AS resp_min,
    MAX(CASE WHEN itemid = 220210 THEN valuenum END) AS resp_max,
    MIN(CASE WHEN itemid IN (223761, 223762) THEN temp_c END) AS temp_min,
    MAX(CASE WHEN itemid IN (223761, 223762) THEN temp_c END) AS temp_max,
    MIN(CASE WHEN itemid = 220277 THEN valuenum END) AS spo2_min,
    COUNT(*) AS total_measurements,
    SUM(
      CASE 
        WHEN (itemid = 220045 AND (valuenum < 60 OR valuenum > 100)) OR
             (itemid IN (220179, 225309) AND valuenum < 90) OR
             (itemid = 220210 AND (valuenum < 12 OR valuenum > 20)) OR
             (itemid IN (223761, 223762) AND 
                ((itemid = 223761 AND ((valuenum - 32)*5/9 < 36 OR (valuenum - 32)*5/9 > 38)) OR 
                 (itemid = 223762 AND (temp_c < 36 OR temp_c > 38))
                )
             ) OR
             (itemid = 220277 AND valuenum < 90)
        THEN 1 
        ELSE 0 
      END
    ) AS total_abnormal
  FROM vitals
  GROUP BY stay_id
),
patient_outcomes AS (
  SELECT 
    c.stay_id,
    c.hhs_flag,
    c.icu_los,
    c.hospital_expire_flag,
    -- Composite instability score (0-5 points)
    (CASE WHEN va.hr_min < 60 OR va.hr_max > 100 THEN 1 ELSE 0 END) +
    (CASE WHEN va.sbp_min < 90 THEN 1 ELSE 0 END) +
    (CASE WHEN va.resp_min < 12 OR va.resp_max > 20 THEN 1 ELSE 0 END) +
    (CASE WHEN va.temp_min < 36 OR va.temp_max > 38 THEN 1 ELSE 0 END) +
    (CASE WHEN va.spo2_min < 90 THEN 1 ELSE 0 END) AS instability_score,
    -- Abnormal-vital burden
    va.total_abnormal / va.total_measurements AS abnormal_burden
  FROM cohort c
  LEFT JOIN vitals_agg va
    ON c.stay_id = va.stay_id
  WHERE va.total_measurements > 0  -- Exclude patients with no vitals
)
SELECT 
  CASE 
    WHEN hhs_flag = 1 THEN 'HHS' 
    ELSE 'Control' 
  END AS group_name,
  COUNT(*) AS n_patients,
  -- Instability Score: 25th, 50th, 75th percentiles
  APPROX_QUANTILES(instability_score, 4)[OFFSET(1)] AS q1_instability_score,
  APPROX_QUANTILES(instability_score, 4)[OFFSET(2)] AS median_instability_score,
  APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS q3_instability_score,
  -- Abnormal-Vital Burden: 25th, 50th, 75th percentiles
  APPROX_QUANTILES(abnormal_burden, 4)[OFFSET(1)] AS q1_abnormal_burden,
  APPROX_QUANTILES(abnormal_burden, 4)[OFFSET(2)] AS median_abnormal_burden,
  APPROX_QUANTILES(abnormal_burden, 4)[OFFSET(3)] AS q3_abnormal_burden,
  -- ICU LOS: 25th, 50th, 75th percentiles
  APPROX_QUANTILES(icu_los, 4)[OFFSET(1)] AS q1_icu_los,
  APPROX_QUANTILES(icu_los, 4)[OFFSET(2)] AS median_icu_los,
  APPROX_QUANTILES(icu_los, 4)[OFFSET(3)] AS q3_icu_los,
  -- Mortality
  SUM(hospital_expire_flag) AS deaths,
  AVG(hospital_expire_flag) AS mortality_rate
FROM patient_outcomes
GROUP BY hhs_flag
ORDER BY hhs_flag DESC;