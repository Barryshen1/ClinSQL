WITH cohort AS (
  -- Base cohort: female, 87-97yo, first ICU stay, lower GI bleed
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    a.deathtime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) AS rn_stay
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON CAST(i.hadm_id AS STRING) = a.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE 
        d.hadm_id = CAST(i.hadm_id AS STRING)
        AND d.icd_version = '10'
        AND d.icd_code LIKE 'K92.%'
        AND dd.long_title LIKE '%bleeding%'  -- Refine to bleeding-specific
    )
),
analysis AS (
  SELECT 
    c.subject_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.deathtime,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile,
    procedure_count
  FROM (
    SELECT 
      c.*,
      COUNT(DISTINCT pe.itemid) AS procedure_count
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON c.stay_id = pe.stay_id
      AND pe.starttime >= c.intime
      AND pe.starttime <= TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    WHERE c.rn_stay = 1  -- First stay only
    GROUP BY 
      c.subject_id, c.stay_id, c.hadm_id, c.intime, c.outtime, c.deathtime, c.anchor_age, c.rn_stay
  ) c
)
SELECT 
  quintile,
  ROUND(AVG(procedure_count), 2) AS mean_procedure_count,
  ROUND(AVG(TIMESTAMP_DIFF(outtime, intime, HOUR) / 24.0), 2) AS mean_icu_los_days,
  ROUND(AVG(CASE WHEN deathtime IS NOT NULL THEN 1.0 ELSE 0 END) * 100, 2) AS in_hospital_mortality_pct
FROM analysis
GROUP BY quintile
ORDER BY quintile;