WITH pe_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    dd.icd_code IN ('I260', 'I261', 'I262', 'I263', 'I264', 'I265', 'I266', 'I268', 'I269')
    AND dd.icd_version = 10
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
),

meds_first24hr AS (
  SELECT
    e.hadm_id,
    COUNT(DISTINCT e.medication) AS med_count,
    COUNT(DISTINCT CASE 
      WHEN LOWER(e.medication) LIKE '%amiodarone%' 
        OR LOWER(e.medication) LIKE '%sotalol%' 
        OR LOWER(e.medication) LIKE '%levofloxacin%' 
      THEN e.medication 
    END) AS qt_prolonging,
    COUNT(DISTINCT CASE 
      WHEN LOWER(e.medication) LIKE '%warfarin%' 
        OR LOWER(e.medication) LIKE '%heparin%' 
      THEN e.medication 
    END) AS bleeding_risk
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN pe_admissions pa ON e.hadm_id = pa.hadm_id
  WHERE e.charttime BETWEEN pa.admittime AND DATETIME_ADD(pa.admittime, INTERVAL 24 HOUR)
  GROUP BY e.hadm_id
),

med_complexity_stats AS (
  SELECT
    AVG(med_count) AS mean_complexity,
    MIN(med_count) AS min_complexity,
    MAX(med_count) AS max_complexity,
    STDDEV(med_count) AS stddev_complexity
  FROM meds_first24hr
),

mean_percentile_stat AS (
  SELECT AVG(percentile) AS mean_percentile
  FROM (
    SELECT med_count, PERCENT_RANK() OVER (ORDER BY med_count) AS percentile
    FROM meds_first24hr
  )
),

icu_flag AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN stay_id IS NOT NULL THEN 1 ELSE 0 END) AS icu_admitted
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),

los_75th_percentile AS (
  SELECT
    PERCENTILE_CONT(los_days, 0.75) OVER() AS los_75
  FROM pe_admissions
  LIMIT 1
),

los_mortality AS (
  SELECT
    hadm_id,
    los_days,
    hospital_expire_flag
  FROM pe_admissions
)

SELECT
  mcs.mean_complexity,
  mcs.min_complexity,
  mcs.max_complexity,
  mcs.stddev_complexity,
  mps.mean_percentile,
  AVG(COALESCE(mf.qt_prolonging, 0)) AS avg_qt_prolonging,
  AVG(COALESCE(mf.bleeding_risk, 0)) AS avg_bleeding_risk,
  AVG(COALESCE(icu.icu_admitted, 0)) AS icu_admission_rate,
  AVG(CASE WHEN lm.los_days >= l75.los_75 THEN 1 ELSE 0 END) AS top_quartile_los_rate,
  AVG(lm.hospital_expire_flag) AS mortality_rate
FROM med_complexity_stats mcs
CROSS JOIN mean_percentile_stat mps
CROSS JOIN los_75th_percentile l75
LEFT JOIN meds_first24hr mf ON TRUE
LEFT JOIN icu_flag icu ON mf.hadm_id = icu.hadm_id
LEFT JOIN los_mortality lm ON mf.hadm_id = lm.hadm_id
GROUP BY 1,2,3,4,5, l75.los_75;