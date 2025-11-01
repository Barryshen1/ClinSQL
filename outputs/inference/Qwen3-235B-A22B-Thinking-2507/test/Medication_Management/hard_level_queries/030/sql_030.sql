WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 71 AND 81
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE (icd_version = 9 AND icd_code = '5770')
         OR (icd_version = 10 AND icd_code LIKE 'K85.%')
    )
),
med_admin AS (
  -- Ward medications (emar)
  SELECT 
    e.hadm_id,
    e.charttime AS admin_time,
    e.medication
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  INNER JOIN cohort c
    ON e.hadm_id = c.hadm_id
  WHERE e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  UNION ALL
  -- ICU medications (inputevents)
  SELECT 
    i.hadm_id,
    i.starttime AS admin_time,
    i.ordercomponenttypedescription AS medication
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
  INNER JOIN cohort c
    ON i.hadm_id = c.hadm_id
  WHERE i.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND i.ordercomponenttypedescription IS NOT NULL
),
complexity AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT medication) AS complexity_score
  FROM med_admin
  GROUP BY hadm_id
),
tertiles AS (
  SELECT 
    c.hadm_id,
    c.complexity_score,
    NTILE(3) OVER (ORDER BY c.complexity_score) AS tertile
  FROM complexity c
),
readmissions AS (
  SELECT 
    c.hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmit30
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON c.subject_id = a2.subject_id
    AND a2.admittime > c.dischtime
    AND a2.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
),
outcomes AS (
  SELECT 
    t.hadm_id,
    t.tertile,
    t.complexity_score,
    c.hospital_expire_flag,
    r.readmit30,
    DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days
  FROM tertiles t
  INNER JOIN cohort c ON t.hadm_id = c.hadm_id
  LEFT JOIN readmissions r ON t.hadm_id = r.hadm_id
)
SELECT 
  tertile,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  AVG(los_days) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(readmit30) AS readmission_rate
FROM outcomes
GROUP BY tertile
ORDER BY tertile;