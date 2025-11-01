WITH first_icu AS (
  SELECT 
    icu.*,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
first_icu_ranked AS (
  SELECT 
    *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS stay_rank
  FROM first_icu
),
base_cohort AS (
  SELECT *
  FROM first_icu_ranked
  WHERE stay_rank = 1
    AND age_at_icu BETWEEN 83 AND 93
),
sepsis_cohort AS (
  SELECT bc.*
  FROM base_cohort bc
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    WHERE diag.hadm_id = bc.hadm_id
      AND diag.icd_version = 10
      AND (
        diag.icd_code LIKE 'A40%' 
        OR diag.icd_code LIKE 'A41%' 
        OR diag.icd_code LIKE 'R652%'
      )
  )
),
procedure_counts AS (
  SELECT 
    sc.subject_id,
    sc.hadm_id,
    sc.stay_id,
    COALESCE(lab_count, 0) + COALESCE(micro_count, 0) AS total_distinct_procedures
  FROM sepsis_cohort sc
  LEFT JOIN (
    SELECT 
      le.subject_id, 
      le.hadm_id, 
      sc.stay_id,
      COUNT(DISTINCT le.itemid) AS lab_count
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN sepsis_cohort AS sc
      ON le.subject_id = sc.subject_id AND le.hadm_id = sc.hadm_id
    WHERE le.charttime >= sc.intime
      AND le.charttime <= TIMESTAMP_ADD(sc.intime, INTERVAL 72 HOUR)
    GROUP BY le.subject_id, le.hadm_id, sc.stay_id
  ) AS lab ON sc.subject_id = lab.subject_id AND sc.hadm_id = lab.hadm_id AND sc.stay_id = lab.stay_id
  LEFT JOIN (
    SELECT 
      me.subject_id, 
      me.hadm_id, 
      sc.stay_id,
      COUNT(DISTINCT me.test_itemid) AS micro_count
    FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents` AS me
    INNER JOIN sepsis_cohort AS sc
      ON me.subject_id = sc.subject_id AND me.hadm_id = sc.hadm_id
    WHERE me.charttime >= sc.intime
      AND me.charttime <= TIMESTAMP_ADD(sc.intime, INTERVAL 72 HOUR)
    GROUP BY me.subject_id, me.hadm_id, sc.stay_id
  ) AS micro ON sc.subject_id = micro.subject_id AND sc.hadm_id = micro.hadm_id AND sc.stay_id = micro.stay_id
),
cohort_with_los_mort AS (
  SELECT 
    pc.subject_id,
    pc.hadm_id,
    pc.stay_id,
    pc.total_distinct_procedures,
    sc.los,
    adm.hospital_expire_flag
  FROM procedure_counts pc
  INNER JOIN sepsis_cohort sc
    ON pc.subject_id = sc.subject_id AND pc.hadm_id = sc.hadm_id AND pc.stay_id = sc.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pc.hadm_id = adm.hadm_id
),
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY total_distinct_procedures) AS quartile
  FROM cohort_with_los_mort
)
SELECT
  quartile,
  AVG(total_distinct_procedures) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_percent
FROM quartiles
GROUP BY quartile
ORDER BY quartile;