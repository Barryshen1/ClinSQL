WITH sepsis_patients AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 90 AND 100
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.hadm_id = i.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '038%')
          OR (d.icd_version = 10 AND d.icd_code BETWEEN 'A40' AND 'A41')
        )
    )
),
diagnostic_counts AS (
  SELECT 
    sp.stay_id,
    COUNT(l.labevent_id) AS diagnostic_count
  FROM sepsis_patients sp
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON sp.hadm_id = l.hadm_id
    AND l.charttime BETWEEN sp.intime AND TIMESTAMP_ADD(sp.intime, INTERVAL 24 HOUR)
  GROUP BY sp.stay_id
),
mortality AS (
  SELECT 
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct
  FROM sepsis_patients
),
los AS (
  SELECT 
    AVG(los) AS avg_los
  FROM sepsis_patients
),
admissions_vs_icu AS (
  SELECT 
    COUNT(DISTINCT hadm_id) AS num_admissions,
    COUNT(stay_id) AS num_icu_stays
  FROM sepsis_patients
)
SELECT 
  STDDEV(diagnostic_count) AS sd_diagnostic_utilization,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY diagnostic_count) AS p75,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY diagnostic_count) AS p95,
  mortality.mortality_pct,
  los.avg_los,
  admissions_vs_icu.num_admissions,
  admissions_vs_icu.num_icu_stays
FROM diagnostic_counts
CROSS JOIN mortality
CROSS JOIN los
CROSS JOIN admissions_vs_icu;