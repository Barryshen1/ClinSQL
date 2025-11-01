WITH cohort AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
),
hfnc_flag AS (
  SELECT DISTINCT
    c.stay_id,
    TRUE AS hfnc
  FROM
    cohort AS c
    JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
      ON c.stay_id = pe.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON pe.itemid = di.itemid
     AND LOWER(di.label) LIKE '%high flow nasal cannula%'
  WHERE
    pe.starttime BETWEEN c.intime
                   AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
),
-- Per‐stay instability‐score percentiles
inst_metrics AS (
  SELECT
    c.stay_id,
    IF(h.hfnc IS TRUE, 'HFNC', 'Control') AS group_label,
    PERCENTILE_CONT(ce.valuenum, 0.25) AS inst_p25,
    PERCENTILE_CONT(ce.valuenum, 0.50) AS inst_median,
    PERCENTILE_CONT(ce.valuenum, 0.75) AS inst_p75,
    PERCENTILE_CONT(ce.valuenum, 0.95) AS inst_p95
  FROM
    cohort AS c
    LEFT JOIN hfnc_flag AS h
      ON c.stay_id = h.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON c.stay_id = ce.stay_id
     AND ce.charttime BETWEEN c.intime AND c.outtime
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON ce.itemid = di.itemid
     AND LOWER(di.label) LIKE '%instability score%'
  GROUP BY
    c.stay_id,
    group_label
),
-- Per‐stay tachycardia, hypotension, LOS, mortality
stay_metrics AS (
  SELECT
    c.stay_id,
    IF(h.hfnc IS TRUE, 'HFNC', 'Control') AS group_label,
    SUM(CASE WHEN hr.valuenum > 100 THEN 1 ELSE 0 END) * 1.0
      / NULLIF(COUNT(hr.valuenum), 0) AS tachy_burden,
    SUM(CASE WHEN mv.valuenum < 65 THEN 1 ELSE 0 END) * 1.0
      / NULLIF(COUNT(mv.valuenum), 0) AS hypo_burden,
    ic.los,
    adm.hospital_expire_flag AS died_in_hosp
  FROM
    cohort AS c
    LEFT JOIN hfnc_flag AS h
      ON c.stay_id = h.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
      ON c.stay_id = ic.stay_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON c.hadm_id = adm.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS hr
      ON c.stay_id = hr.stay_id
     AND hr.charttime BETWEEN c.intime AND c.outtime
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS dih
      ON hr.itemid = dih.itemid
     AND LOWER(dih.label) LIKE '%heart rate%'
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS mv
      ON c.stay_id = mv.stay_id
     AND mv.charttime BETWEEN c.intime AND c.outtime
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS dim
      ON mv.itemid = dim.itemid
     AND LOWER(dim.label) LIKE '%mean arterial pressure%'
  GROUP BY
    c.stay_id,
    group_label,
    ic.los,
    adm.hospital_expire_flag
),
-- Combine per‐stay metrics
combined AS (
  SELECT
    s.stay_id,
    s.group_label,
    i.inst_p25,
    i.inst_median,
    i.inst_p75,
    i.inst_p95,
    s.tachy_burden,
    s.hypo_burden,
    s.los,
    s.died_in_hosp
  FROM
    stay_metrics AS s
    JOIN inst_metrics AS i
      ON s.stay_id = i.stay_id
)
-- Final group‐level summaries
SELECT
  group_label,
  -- Instability score percentiles across stays
  PERCENTILE_CONT(inst_p25, 0.25) AS inst_score_p25,
  PERCENTILE_CONT(inst_median, 0.50) AS inst_score_median,
  PERCENTILE_CONT(inst_p75, 0.75) AS inst_score_p75,
  PERCENTILE_CONT(inst_p95, 0.95) AS inst_score_p95,
  -- Tachycardia & hypotension burden medians
  PERCENTILE_CONT(tachy_burden, 0.50) AS tachycardia_burden_median,
  PERCENTILE_CONT(hypo_burden, 0.50) AS hypotension_burden_median,
  -- ICU LOS median
  PERCENTILE_CONT(los, 0.50) AS icu_los_median,
  -- Mortality rate
  SUM(CASE WHEN died_in_hosp = 1 THEN 1 ELSE 0 END) * 1.0
    / COUNT(*) AS mortality_rate
FROM
  combined
GROUP BY
  group_label
ORDER BY
  group_label;