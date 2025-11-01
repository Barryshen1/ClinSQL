WITH first_icu_stays AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.los,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'M'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ie.subject_id ORDER BY ie.intime) = 1
),

sepsis_cohort AS (
  SELECT 
    fi.subject_id, 
    fi.hadm_id, 
    fi.stay_id,
    fi.intime,
    fi.los,
    adm.hospital_expire_flag
  FROM first_icu_stays fi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON fi.hadm_id = adm.hadm_id
  WHERE 
    fi.age_at_admission BETWEEN 83 AND 93
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        diag.hadm_id = fi.hadm_id AND
        (
          (diag.icd_version = 9 AND diag.icd_code IN ('038', '0200', '78552', '99591', '99592')) OR
          (diag.icd_version = 10 AND (diag.icd_code LIKE 'A40%' OR diag.icd_code LIKE 'A41%' OR diag.icd_code IN ('R6520', 'R6521')))
        )
    )
),

procedure_counts AS (
  SELECT 
    sc.stay_id,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM sepsis_cohort sc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON sc.stay_id = pe.stay_id
    AND pe.starttime >= sc.intime
    AND pe.starttime <= TIMESTAMP_ADD(sc.intime, INTERVAL 72 HOUR)
  GROUP BY sc.stay_id
),

cohort_with_quartiles AS (
  SELECT 
    sc.*,
    pc.proc_count,
    NTILE(4) OVER (ORDER BY pc.proc_count) AS quartile
  FROM sepsis_cohort sc
  INNER JOIN procedure_counts pc
    ON sc.stay_id = pc.stay_id
)

SELECT
  quartile,
  AVG(proc_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  100.0 * AVG(hospital_expire_flag) AS mortality_percent
FROM cohort_with_quartiles
GROUP BY quartile
ORDER BY quartile;