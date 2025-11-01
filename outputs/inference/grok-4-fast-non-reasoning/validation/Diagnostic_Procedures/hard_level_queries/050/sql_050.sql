WITH cohort AS (
  -- Base cohort: male, 76-86, AMI, first ICU stay
  SELECT 
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND d.hadm_id = a.hadm_id
  INNER JOIN (
    SELECT subject_id, hadm_id,
           ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn_stay
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) first_stay
    ON i.subject_id = first_stay.subject_id 
    AND i.hadm_id = first_stay.hadm_id 
    AND first_stay.rn_stay = 1
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND (
      (d.icd_version = '10' AND d.icd_code LIKE 'I21%') OR
      (d.icd_version = '9' AND d.icd_code LIKE '410%')
    )
),
procedure_counts AS (
  -- Distinct procedures in first 24h of first ICU stay
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
    AND pe.starttime >= c.intime 
    AND pe.starttime < TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
aggregated AS (
  -- Add procedure count to cohort (left join for zeros), assign quartiles
  SELECT 
    c.*,
    COALESCE(pc.procedure_count, 0) AS procedure_count,
    NTILE(4) OVER (ORDER BY COALESCE(pc.procedure_count, 0)) AS quartile
  FROM cohort c
  LEFT JOIN procedure_counts pc
    ON c.subject_id = pc.subject_id 
    AND c.hadm_id = pc.hadm_id 
    AND c.stay_id = pc.stay_id
)
SELECT 
  CASE 
    WHEN quartile = 1 THEN 'Q1 (Lowest)'
    WHEN quartile = 2 THEN 'Q2'
    WHEN quartile = 3 THEN 'Q3'
    WHEN quartile = 4 THEN 'Q4 (Highest)'
  END AS quartile_str,
  ROUND(AVG(procedure_count), 2) AS mean_procedure_count,
  ROUND(AVG(los), 2) AS mean_icu_los_days,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT)) * 100, 2) AS hospital_mortality_pct,
  COUNT(*) AS n_patients
FROM aggregated
GROUP BY quartile
ORDER BY quartile;