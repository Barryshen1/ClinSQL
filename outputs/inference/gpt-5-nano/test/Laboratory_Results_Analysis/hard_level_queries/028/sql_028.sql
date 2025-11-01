WITH ich_population AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 74 AND 84
    AND (
         dd.long_title LIKE '%intracranial hemorrhage%'
         OR dd.long_title LIKE '%intracerebral hemorrhage%'
         OR dd.long_title LIKE '%intracranial bleed%'
        )
),

ich_lab AS (
  SELECT
    ih.hadm_id,
    ih.subject_id,
    ih.admittime,
    ih.dischtime,
    ih.hospital_expire_flag,
    (TIMESTAMP_DIFF(ih.dischtime, ih.admittime, SECOND) / 86400.0) AS los_days,
    COUNT(DISTINCT le.itemid) AS unstable_lab_count
  FROM ich_population ih
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.subject_id = ih.subject_id
   AND le.hadm_id = ih.hadm_id
   AND le.charttime >= ih.admittime
   AND le.charttime <= TIMESTAMP_ADD(ih.admittime, INTERVAL 72 HOUR)
   AND le.valuenum IS NOT NULL
   AND ( (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
         OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper) )
  GROUP BY ih.hadm_id, ih.subject_id, ih.admittime, ih.dischtime, ih.hospital_expire_flag, los_days
),

ich_quint AS (
  SELECT
    ih.hadm_id,
    ih.subject_id,
    ih.admittime,
    ih.dischtime,
    ih.hospital_expire_flag,
    ih.los_days,
    ih.unstable_lab_count,
    NTILE(5) OVER (ORDER BY ih.unstable_lab_count) AS quintile
  FROM ich_lab ih
),

ich_crit AS (
  SELECT
    q.hadm_id,
    q.subject_id,
    q.quintile,
    MAX(CASE WHEN LOWER(le.flag) LIKE '%critical%' THEN 1 ELSE 0 END) AS has_critical
  FROM ich_quint q
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.subject_id = q.subject_id
   AND le.hadm_id = q.hadm_id
   AND le.charttime >= q.admittime
   AND le.charttime <= TIMESTAMP_ADD(q.admittime, INTERVAL 72 HOUR)
  GROUP BY q.hadm_id, q.subject_id, q.quintile
),

ich_final AS (
  SELECT
    iq.hadm_id,
    iq.subject_id,
    iq.admittime,
    iq.dischtime,
    iq.hospital_expire_flag,
    iq.los_days,
    iq.unstable_lab_count,
    iq.quintile,
    COALESCE(ic.has_critical, 0) AS has_critical
  FROM ich_quint iq
  LEFT JOIN ich_crit ic
    ON iq.hadm_id = ic.hadm_id
   AND iq.subject_id = ic.subject_id
   AND iq.quintile = ic.quintile
),

controls_population AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 74 AND 84
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd2
        ON di2.icd_code = dd2.icd_code AND di2.icd_version = dd2.icd_version
      WHERE di2.subject_id = a.subject_id AND di2.hadm_id = a.hadm_id
        AND (dd2.long_title LIKE '%intracranial hemorrhage%'
             OR dd2.long_title LIKE '%intracerebral hemorrhage%'
             OR dd2.long_title LIKE '%intracranial bleed%')
  )
),

controls_crit AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    MAX(CASE WHEN LOWER(le.flag) LIKE '%critical%' THEN 1 ELSE 0 END) AS has_critical
  FROM controls_population c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.subject_id = c.subject_id
   AND le.hadm_id = c.hadm_id
   AND le.charttime >= c.admittime
   AND le.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id, c.subject_id
),

control_rate AS (
  SELECT AVG(has_critical) AS control_critical_rate FROM controls_crit
)

SELECT
  ich_final.quintile AS quintile,
  AVG(ich_final.hospital_expire_flag) AS mortality_rate,
  AVG(ich_final.los_days) AS mean_los_days,
  AVG(ich_final.has_critical) AS ich_critical_rate,
  cr.control_critical_rate,
  SAFE_DIVIDE(AVG(ich_final.has_critical), cr.control_critical_rate) AS risk_ratio
FROM ich_final
CROSS JOIN control_rate cr
GROUP BY ich_final.quintile, cr.control_critical_rate
ORDER BY ich_final.quintile;