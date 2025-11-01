WITH cohort AS (
  SELECT DISTINCT
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON i.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND d.icd_version = 10
    AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
),

time_bins AS (
  SELECT 
    stay_id,
    DATETIME_ADD(intime, INTERVAL n HOUR) AS bin_start,
    DATETIME_ADD(intime, INTERVAL n+1 HOUR) AS bin_end
  FROM cohort
  CROSS JOIN UNNEST(GENERATE_ARRAY(0, 47)) AS n
),

all_events AS (
  SELECT 
    tb.stay_id,
    tb.bin_start,
    MAX(CASE 
          WHEN ce.itemid IN (220734, 223761, 223762) AND ce.valuenum > 38.5 THEN 1 
          ELSE 0 
        END) AS fever_flag,
    MAX(CASE 
          WHEN ce.itemid IN (220277, 646) AND ce.valuenum < 90 THEN 1 
          ELSE 0 
        END) AS hypoxemia_flag,
    MAX(CASE 
          WHEN ce.itemid IN (220210, 618) AND ce.valuenum > 20 THEN 1 
          ELSE 0 
        END) AS tachypnea_flag
  FROM time_bins tb
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON tb.stay_id = ce.stay_id
    AND ce.charttime >= tb.bin_start
    AND ce.charttime < tb.bin_end
    AND ce.itemid IN (220734, 223761, 223762, 220277, 646, 220210, 618)
    AND ce.valuenum IS NOT NULL
  GROUP BY tb.stay_id, tb.bin_start
),

per_stay_instability AS (
  SELECT 
    stay_id,
    SUM(fever_flag) AS fever_hours,
    SUM(hypoxemia_flag) AS hypoxemia_hours,
    SUM(tachypnea_flag) AS tachypnea_hours,
    SUM(CASE 
          WHEN fever_flag = 1 OR hypoxemia_flag = 1 OR tachypnea_flag = 1 THEN 1 
          ELSE 0 
        END) AS instability_hours
  FROM all_events
  GROUP BY stay_id
),

cohort_instability AS (
  SELECT 
    c.stay_id,
    c.los,
    c.hospital_expire_flag,
    psi.fever_hours,
    psi.hypoxemia_hours,
    psi.tachypnea_hours,
    psi.instability_hours
  FROM cohort c
  INNER JOIN per_stay_instability psi
    ON c.stay_id = psi.stay_id
),

percentile_90 AS (
  SELECT 
    APPROX_QUANTILES(instability_hours, 100)[OFFSET(90)] AS p90
  FROM cohort_instability
)

SELECT 
  COUNT(*) AS n,
  ROUND(AVG(los), 2) AS mean_icu_los,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_percentage,
  ROUND(AVG(fever_hours), 2) AS mean_fever_hours,
  ROUND(AVG(hypoxemia_hours), 2) AS mean_hypoxemia_hours,
  ROUND(AVG(tachypnea_hours), 2) AS mean_tachypnea_hours
FROM cohort_instability
CROSS JOIN percentile_90
WHERE instability_hours >= p90;