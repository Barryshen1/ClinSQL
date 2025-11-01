WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 44 AND 54
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '410%')
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
        )
    )
),
first_icu AS (
  SELECT 
    i.hadm_id,
    i.stay_id,
    i.intime,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN cohort c
    ON i.hadm_id = c.hadm_id
),
first_icu_filtered AS (
  SELECT 
    hadm_id,
    stay_id,
    intime
  FROM first_icu
  WHERE rn = 1
),
procedure_counts AS (
  SELECT 
    fic.hadm_id,
    COUNT(p.stay_id) AS procedure_count
  FROM first_icu_filtered fic
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON fic.stay_id = p.stay_id
    AND p.starttime >= fic.intime
    AND p.starttime <= fic.intime + INTERVAL '72' HOUR
  GROUP BY fic.hadm_id
),
full_cohort AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    pc.procedure_count,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM cohort c
  INNER JOIN first_icu_filtered fic 
    ON c.hadm_id = fic.hadm_id
  INNER JOIN procedure_counts pc 
    ON c.hadm_id = pc.hadm_id
),
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM full_cohort
)
SELECT 
  quartile,
  COUNT(*) AS n_per_quartile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(los_days) AS mean_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_pct
FROM quartiles
GROUP BY quartile
ORDER BY quartile;