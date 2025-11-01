WITH patients_icu AS (
  -- Male ICU patients aged 40-50
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),

stroke_adms AS (
  -- Admissions with hemorrhagic stroke (ICD-10 I60-I61)
  SELECT DISTINCT sa.subject_id, sa.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = '10'
      AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%')
  ) di ON CAST(a.hadm_id AS STRING) = di.hadm_id
  INNER JOIN patients_icu pi ON a.subject_id = pi.subject_id
  -- One admission per subject (earliest)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
),

cohort_stays AS (
  -- Stroke cohort ICU stays (within 72h of admittime)
  SELECT 'hemorrhagic_stroke' AS cohort_type, i.stay_id, i.subject_id, i.hadm_id, i.intime, i.los, i.outtime,
         DATETIME_ADD(i.intime, INTERVAL 72 HOUR) AS window_end
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN stroke_adms sa ON i.subject_id = sa.subject_id AND CAST(i.hadm_id AS STRING) = CAST(sa.hadm_id AS STRING)
  WHERE i.intime <= DATETIME_ADD(sa.admittime, INTERVAL 72 HOUR)

  UNION ALL

  -- Control cohort: ICU stays without hemorrhagic stroke admission
  SELECT 'other' AS cohort_type, i.stay_id, i.subject_id, i.hadm_id, i.intime, i.los, i.outtime,
         DATETIME_ADD(i.intime, INTERVAL 72 HOUR) AS window_end
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN patients_icu pi ON i.subject_id = pi.subject_id
  WHERE NOT EXISTS (
    SELECT 1 FROM stroke_adms sa
    WHERE i.subject_id = sa.subject_id
      AND CAST(i.hadm_id AS STRING) = CAST(sa.hadm_id AS STRING)
      AND i.intime <= DATETIME_ADD(sa.admittime, INTERVAL 72 HOUR)
  )
),

proc_counts AS (
  -- Count distinct diagnostic procedures in first 72h per stay
  SELECT cs.cohort_type, cs.stay_id,
         COUNT(DISTINCT pe.itemid) AS itemid_count
  FROM cohort_stays cs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON cs.stay_id = pe.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE pe.starttime >= cs.intime
    AND pe.starttime <= cs.window_end
    AND di.category = 'Diagnostic'
    AND pe.itemid IS NOT NULL  -- Exclude invalid
  GROUP BY cs.cohort_type, cs.stay_id
),

mortality AS (
  -- In-hospital mortality per cohort (via hadm_id)
  SELECT cs.cohort_type,
         AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM cohort_stays cs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON CAST(cs.hadm_id AS STRING) = CAST(a.hadm_id AS STRING)
  GROUP BY cs.cohort_type
)

-- Final metrics: 90th percentile procedures, avg LOS, mortality
SELECT 
  pc.cohort_type,
  PERCENTILE_CONT(pc.itemid_count, 0.9) OVER (PARTITION BY pc.cohort_type) AS p90_diagnostic_procedures,
  AVG(cs.los) AS avg_icu_los_days,
  m.mortality_rate
FROM proc_counts pc
INNER JOIN cohort_stays cs ON pc.stay_id = cs.stay_id
INNER JOIN mortality m ON pc.cohort_type = m.cohort_type
GROUP BY pc.cohort_type, m.mortality_rate
ORDER BY pc.cohort_type;