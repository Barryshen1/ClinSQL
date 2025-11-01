WITH hem_stroke_hadms AS (
  -- Identify admissions with hemorrhagic stroke diagnosis
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%hemorrhag%stroke%'
),

cohort AS (
  -- Male ICU patients aged 40-50
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    p.anchor_age,
    a.hospital_expire_flag,
    CASE
      WHEN hs.hadm_id IS NOT NULL THEN 'hemorrhagic_stroke'
      ELSE 'other'
    END AS stroke_group
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ic.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ic.subject_id = a.subject_id
   AND ic.hadm_id = a.hadm_id
  LEFT JOIN hem_stroke_hadms hs
    ON ic.hadm_id = hs.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),

proc_counts AS (
  -- Count procedures in first 72h of ICU stay
  SELECT
    ic.stay_id,
    COUNT(pr.seq_num) AS proc_count
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON ic.subject_id = pr.subject_id
   AND ic.hadm_id    = pr.hadm_id
   AND pr.chartdate BETWEEN DATE(ic.intime)
                      AND DATE_ADD(DATE(ic.intime), INTERVAL 3 DAY)
  GROUP BY ic.stay_id
)

SELECT
  c.stroke_group,
  -- 90th percentile of diagnostic procedure counts
  APPROX_QUANTILES(IFNULL(pc.proc_count, 0), 100)[OFFSET(90)] AS pct90_proc_count,
  -- Average ICU LOS
  AVG(c.los) AS avg_icu_los,
  -- In-hospital mortality rate
  AVG(c.hospital_expire_flag) AS mortality_rate
FROM cohort c
LEFT JOIN proc_counts pc
  ON c.stay_id = pc.stay_id
GROUP BY c.stroke_group
ORDER BY c.stroke_group;