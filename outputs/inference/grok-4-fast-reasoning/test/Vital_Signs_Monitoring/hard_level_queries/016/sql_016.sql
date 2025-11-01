WITH transplant_hadm AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    icd_version = 9 
    AND icd_code IN ('V42.0', 'V42.1', 'V42.2', 'V42.5', 'V42.6', 'V42.81', 'V42.82')
  ) OR (
    icd_version = 10 
    AND icd_code IN ('Z94.0', 'Z94.1', 'Z94.2', 'Z94.3', 'Z94.4', 'Z94.6')
  )
),
icu_cohort AS (
  SELECT 
    si.stay_id, si.subject_id, si.hadm_id, si.intime, si.los,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM si.intime) - p.anchor_year + p.anchor_age AS age,
    CASE WHEN t.hadm_id IS NOT NULL THEN 'Transplant' ELSE 'Non-Transplant' END AS group_type
  FROM (
    SELECT 
      si.*,
      ROW_NUMBER() OVER (PARTITION BY si.subject_id ORDER BY si.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` si
  ) si
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON si.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON si.subject_id = p.subject_id
  LEFT JOIN transplant_hadm t ON si.subject_id = t.subject_id AND si.hadm_id = t.hadm_id
  WHERE si.rn = 1
    AND p.gender = 'M'
    AND (EXTRACT(YEAR FROM si.intime) - p.anchor_year + p.anchor_age) BETWEEN 57 AND 67
),
instability AS (
  SELECT 
    ce.stay_id,
    COUNT(*) AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN icu_cohort ic ON ce.stay_id = ic.stay_id
  WHERE ce.charttime >= ic.intime
    AND ce.charttime <= DATETIME_ADD(ic.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
    AND (
      (ce.itemid IN (676, 677, 678, 679, 681, 682) AND ce.valuenum > 38.5 AND ce.valueuom = 'C')
      OR (ce.itemid = 220277 AND ce.valuenum < 90)
      OR (ce.itemid IN (618, 619, 220210) AND ce.valuenum > 20)
    )
  GROUP BY ce.stay_id
)
SELECT 
  group_type,
  APPROX_QUANTILES(COALESCE(i.instability_score, 0), 4)[OFFSET(1)] AS p25_score,
  APPROX_QUANTILES(COALESCE(i.instability_score, 0), 4)[OFFSET(2)] AS median_score,
  APPROX_QUANTILES(COALESCE(i.instability_score, 0), 4)[OFFSET(3)] AS p75_score,
  APPROX_QUANTILES(ic.los, 4)[OFFSET(1)] AS p25_los,
  APPROX_QUANTILES(ic.los, 4)[OFFSET(2)] AS median_los,
  APPROX_QUANTILES(ic.los, 4)[OFFSET(3)] AS p75_los,
  AVG(ic.hospital_expire_flag) AS mortality_rate,
  COUNT(*) AS n_patients
FROM icu_cohort ic
LEFT JOIN instability i ON ic.stay_id = i.stay_id
GROUP BY group_type
ORDER BY 
  CASE WHEN group_type = 'Transplant' THEN 1 ELSE 2 END;