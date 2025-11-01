WITH
  -- Get vasopressor itemids from d_items
  vasopressor_itemids AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE category = 'medication'
      AND label IN (
        'norepinephrine', 'epinephrine', 'dopamine', 'vasopressin', 
        'phenylephrine', 'dobutamine', 'isoproterenol', 'metaraminol',
        'epinephrine (adrenaline)', 'norepinephrine (levophed)'
      )
  ),
  -- Eligible ICU patients (first ICU stay per patient)
  eligible_icu AS (
    SELECT
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      p.anchor_age,
      p.gender
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON i.subject_id = p.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 68 AND 78
    QUALIFY ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) = 1
  ),
  -- Vasopressor check in first 72 hours
  vasopressors AS (
    SELECT
      e.subject_id,
      e.hadm_id,
      e.stay_id,
      MAX(CASE WHEN vi.itemid IS NOT NULL THEN 1 ELSE 0 END) AS has_vasopressor
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` e
    INNER JOIN eligible_icu icu
      ON e.subject_id = icu.subject_id AND e.hadm_id = icu.hadm_id AND e.stay_id = icu.stay_id
    LEFT JOIN vasopressor_itemids vi
      ON e.itemid = vi.itemid
    WHERE e.starttime BETWEEN icu.intime AND icu.intime + INTERVAL 72 HOUR
    GROUP BY e.subject_id, e.hadm_id, e.stay_id
  ),
  -- Diagnostic load (labs and imaging)
  diagnostic_load AS (
    SELECT
      icu.subject_id,
      icu.hadm_id,
      icu.stay_id,
      COUNT(DISTINCT le.labevent_id) AS lab_count,
      COUNT(DISTINCT CONCAT(h.chartdate, CAST(h.seq_num AS STRING))) AS imaging_count,
      COUNT(DISTINCT le.labevent_id) + COUNT(DISTINCT CONCAT(h.chartdate, CAST(h.seq_num AS STRING))) AS total_diagnostic_load
    FROM eligible_icu icu
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON icu.subject_id = le.subject_id AND icu.hadm_id = le.hadm_id
      AND le.charttime BETWEEN icu.intime AND icu.intime + INTERVAL 72 HOUR
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
      ON icu.subject_id = h.subject_id AND icu.hadm_id = h.hadm_id
      AND h.chartdate BETWEEN DATE(icu.intime) AND DATE(icu.intime + INTERVAL 72 HOUR)
      AND (h.hcpcs_cd LIKE '7%' OR h.hcpcs_cd LIKE '8%')
    GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
  ),
  -- Procedures in 72 hours
  procedures AS (
    SELECT
      icu.subject_id,
      icu.hadm_id,
      icu.stay_id,
      COUNT(*) AS procedure_count -- Count all procedure records
    FROM eligible_icu icu
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
      ON icu.subject_id = p.subject_id AND icu.hadm_id = p.hadm_id
      AND p.chartdate BETWEEN DATE(icu.intime) AND DATE(icu.intime + INTERVAL 72 HOUR)
    GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
  ),
  -- Readmission within 30 days
  readmissions AS (
    SELECT
      a1.subject_id,
      a1.hadm_id,
      MAX(CASE WHEN a2.admittime BETWEEN a1.dischtime AND a1.dischtime + INTERVAL 30 DAY THEN 1 ELSE 0 END) AS readmitted
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
      ON a1.subject_id = a2.subject_id
      AND a2.admittime > a1.dischtime
      AND a2.admittime <= a1.dischtime + INTERVAL 30 DAY
    GROUP BY a1.subject_id, a1.hadm_id
  ),
  -- Combine all data
  combined AS (
    SELECT
      icu.subject_id,
      icu.hadm_id,
      icu.stay_id,
      icu.intime,
      icu.admittime,
      icu.dischtime,
      icu.hospital_expire_flag,
      icu.anchor_age,
      icu.gender,
      v.has_vasopressor,
      dl.total_diagnostic_load,
      p.procedure_count,
      DATE_DIFF(CAST(icu.dischtime AS DATE), CAST(icu.admittime AS DATE), DAY) AS los_days,
      r.readmitted
    FROM eligible_icu icu
    LEFT JOIN vasopressors v
      ON icu.subject_id = v.subject_id AND icu.hadm_id = v.hadm_id AND icu.stay_id = v.stay_id
    LEFT JOIN diagnostic_load dl
      ON icu.subject_id = dl.subject_id AND icu.hadm_id = dl.hadm_id AND icu.stay_id = dl.stay_id
    LEFT JOIN procedures p
      ON icu.subject_id = p.subject_id AND icu.hadm_id = p.hadm_id AND icu.stay_id = p.stay_id
    LEFT JOIN readmissions r
      ON icu.subject_id = r.subject_id AND icu.hadm_id = r.hadm_id
    WHERE v.has_vasopressor = 1
  ),
  -- Assign quartiles for diagnostic load
  with_quartiles AS (
    SELECT
      *,
      NTILE(4) OVER (ORDER BY total_diagnostic_load) AS diagnostic_quartile
    FROM combined
  )
-- Final aggregation by quartile
SELECT
  diagnostic_quartile,
  AVG(procedure_count) AS avg_procedure_count,
  AVG(los_days) AS avg_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate,
  AVG(CAST(readmitted AS FLOAT64)) AS readmission_rate_30d
FROM with_quartiles
GROUP BY diagnostic_quartile
ORDER BY diagnostic_quartile;