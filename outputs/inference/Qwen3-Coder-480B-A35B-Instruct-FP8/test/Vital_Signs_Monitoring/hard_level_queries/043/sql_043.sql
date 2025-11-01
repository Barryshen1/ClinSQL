WITH respiratory_patients AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE d_dx.long_title LIKE '%respiratory failure%'
),

cohort AS (
  SELECT
    rp.subject_id,
    rp.hadm_id,
    rp.stay_id,
    rp.intime,
    rp.outtime,
    rp.los,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM respiratory_patients rp
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON rp.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON rp.hadm_id = a.hadm_id
  WHERE p.anchor_age BETWEEN 40 AND 50
    AND p.gender = 'M'
),

vitals AS (
  SELECT
    ce.stay_id,
    ce.charttime,
    MAX(CASE WHEN di.label LIKE '%Heart Rate%' THEN ce.valuenum ELSE NULL END) AS heart_rate,
    MAX(CASE WHEN di.label LIKE '%MAP%' THEN ce.valuenum ELSE NULL END) AS map
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.charttime IS NOT NULL
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND di.label IN ('Heart Rate', 'MAP')
  GROUP BY ce.stay_id, ce.charttime
),

vii_events AS (
  SELECT
    v.stay_id,
    SUM(CASE WHEN v.map < 65 OR v.heart_rate > 100 THEN 1 ELSE 0 END) AS vital_instability_index,
    SUM(CASE WHEN v.map < 65 THEN 1 ELSE 0 END) AS hypotension_burden,
    SUM(CASE WHEN v.heart_rate > 100 THEN 1 ELSE 0 END) AS tachycardia_burden
  FROM vitals v
  JOIN cohort c
    ON v.stay_id = c.stay_id
  WHERE v.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY v.stay_id
),

stats AS (
  SELECT
    STDDEV(vii.vital_instability_index) AS vii_sd,
    APPROX_QUANTILES(vii.vital_instability_index, 100)[OFFSET(25)] AS vii_p25,
    APPROX_QUANTILES(vii.vital_instability_index, 100)[OFFSET(50)] AS vii_p50,
    APPROX_QUANTILES(vii.vital_instability_index, 100)[OFFSET(75)] AS vii_p75,
    APPROX_QUANTILES(vii.vital_instability_index, 100)[OFFSET(95)] AS vii_p95
  FROM vii_events vii
),

comparison AS (
  SELECT
    CASE
      WHEN vii.vital_instability_index > 0 THEN 'With VII'
      ELSE 'No VII'
    END AS group_label,
    AVG(COALESCE(vii.hypotension_burden, 0)) AS avg_hypotension_burden,
    AVG(COALESCE(vii.tachycardia_burden, 0)) AS avg_tachycardia_burden,
    AVG(c.los) AS avg_icu_los,
    AVG(c.hospital_expire_flag) AS mortality_rate
  FROM cohort c
  LEFT JOIN vii_events vii
    ON c.stay_id = vii.stay_id
  GROUP BY group_label
)

SELECT
  s.vii_sd,
  s.vii_p25,
  s.vii_p50,
  s.vii_p75,
  s.vii_p95,
  cmp.group_label,
  cmp.avg_hypotension_burden,
  cmp.avg_tachycardia_burden,
  cmp.avg_icu_los,
  cmp.mortality_rate
FROM stats s
CROSS JOIN comparison cmp
ORDER BY cmp.group_label;