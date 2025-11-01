WITH mi_admissions AS (
  -- Admissions with at least one acute myocardial infarction diagnosis
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%myocardial infarction%'
),
procedure_counts AS (
  -- Count distinct procedures per ICU stay within first 24 hours
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.los,
    a.hospital_expire_flag,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.subject_id = a.subject_id
   AND s.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  JOIN mi_admissions mi
    ON s.subject_id = mi.subject_id
   AND s.hadm_id = mi.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON s.stay_id = pe.stay_id
   AND pe.starttime BETWEEN s.intime
                        AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
  GROUP BY
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.los,
    a.hospital_expire_flag
),
quartiled AS (
  -- Assign quartiles based on procedure count
  SELECT
    *,
    NTILE(4) OVER (ORDER BY proc_count) AS quartile
  FROM procedure_counts
)
-- Final aggregation by quartile
SELECT
  quartile,
  ROUND(AVG(proc_count), 2)                     AS mean_procedure_count,
  ROUND(AVG(los), 2)                            AS mean_icu_los_days,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS hospital_mortality_pct
FROM quartiled
GROUP BY quartile
ORDER BY quartile;