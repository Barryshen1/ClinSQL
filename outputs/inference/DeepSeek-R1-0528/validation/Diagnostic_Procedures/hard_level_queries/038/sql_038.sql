WITH first_icu AS (
  SELECT 
    subject_id, 
    hadm_id, 
    stay_id,
    intime,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
cohort_stays AS (
  SELECT 
    fi.stay_id,
    fi.intime
  FROM first_icu fi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm 
    ON fi.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON fi.subject_id = p.subject_id
  WHERE fi.rn = 1
    AND p.gender = 'M'
    AND adm.admittime IS NOT NULL
    AND p.anchor_year IS NOT NULL
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 60 AND 70
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      WHERE diag.hadm_id = fi.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code IN ('430', '431', '432')) 
          OR 
          (diag.icd_version = 10 AND diag.icd_code IN ('I60', 'I61', 'I62'))
        )
    )
),
procedure_counts AS (
  SELECT 
    cs.stay_id,
    COUNT(*) AS procedure_count  -- Fixed: Count procedure events (rows)
  FROM cohort_stays cs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON cs.stay_id = pe.stay_id
    AND pe.starttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 72 HOUR)
  GROUP BY cs.stay_id
)
SELECT 
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] AS procedure_burden_75_percentile
FROM procedure_counts;

-- Part 2: Mean ICU LOS and mortality for cohort vs. general ICU population
WITH first_icu AS (
  SELECT 
    subject_id, 
    hadm_id, 
    stay_id,
    los,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
all_first_stays AS (
  SELECT 
    fi.stay_id,
    fi.los,
    adm.hospital_expire_flag,
    CASE 
      WHEN p.gender = 'M'
        AND adm.admittime IS NOT NULL
        AND p.anchor_year IS NOT NULL
        AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 60 AND 70
        AND EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
          WHERE diag.hadm_id = fi.hadm_id
            AND (
              (diag.icd_version = 9 AND diag.icd_code IN ('430', '431', '432')) 
              OR 
              (diag.icd_version = 10 AND diag.icd_code IN ('I60', 'I61', 'I62'))
            )
        ) THEN 1
      ELSE 0
    END AS in_cohort
  FROM first_icu fi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm 
    ON fi.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON fi.subject_id = p.subject_id
  WHERE fi.rn = 1
)
SELECT 
  'Intracranial Hemorrhage Cohort' AS group_name,
  AVG(los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) AS hospital_mortality_rate
FROM all_first_stays
WHERE in_cohort = 1
UNION ALL
SELECT 
  'General ICU Population' AS group_name,
  AVG(los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) AS hospital_mortality_rate
FROM all_first_stays;