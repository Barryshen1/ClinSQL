WITH cohort AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = i.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'I50%'
    )
),
composite_scores AS (
  SELECT 
    c.stay_id,
    c.subject_id,
    c.hadm_id,
    c.intime,
    c.outtime,
    c.hospital_expire_flag,
    SUM(CASE WHEN ce.itemid = 211 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_count,
    SUM(CASE WHEN ce.itemid = 52 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_low_count,
    SUM(CASE WHEN ce.itemid = 618 AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea_count,
    SUM(CASE WHEN ce.itemid = 211 AND ce.valuenum > 100 THEN 1 ELSE 0 END) +
    SUM(CASE WHEN ce.itemid = 52 AND ce.valuenum < 65 THEN 1 ELSE 0 END) +
    SUM(CASE WHEN ce.itemid = 618 AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS composite_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY c.stay_id, c.subject_id, c.hadm_id, c.intime, c.outtime, c.hospital_expire_flag
),
percentiles AS (
  SELECT 
    APPROX_QUANTILES(composite_score, 100)[OFFSET(99)] AS percentile_99,
    APPROX_QUANTILES(composite_score, 100)[OFFSET(75)] AS q75
  FROM composite_scores
),
top_quartile AS (
  SELECT 
    cs.*
  FROM composite_scores cs
  CROSS JOIN percentiles p
  WHERE cs.composite_score >= p.q75
),
top_quartile_metrics AS (
  SELECT 
    AVG(tachycardia_count) AS avg_tachycardia_top,
    AVG(map_low_count) AS avg_map_low_top,
    AVG(tachypnea_count) AS avg_tachypnea_top,
    AVG(DATETIME_DIFF(outtime, intime, HOUR)) AS avg_los_top,
    AVG(hospital_expire_flag) AS avg_mortality_top
  FROM top_quartile
),
all_icu AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
),
all_metrics AS (
  SELECT 
    a.stay_id,
    a.subject_id,
    a.hadm_id,
    a.intime,
    a.outtime,
    a.hospital_expire_flag,
    SUM(CASE WHEN ce.itemid = 211 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_count,
    SUM(CASE WHEN ce.itemid = 52 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_low_count,
    SUM(CASE WHEN ce.itemid = 618 AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea_count,
    DATETIME_DIFF(a.outtime, a.intime, HOUR) AS los_hours
  FROM all_icu a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON a.stay_id = ce.stay_id
    AND ce.charttime BETWEEN a.intime AND DATETIME_ADD(a.intime, INTERVAL 72 HOUR)
  GROUP BY a.stay_id, a.subject_id, a.hadm_id, a.intime, a.outtime, a.hospital_expire_flag
),
all_metrics_avg AS (
  SELECT 
    AVG(tachycardia_count) AS avg_tachycardia_all,
    AVG(map_low_count) AS avg_map_low_all,
    AVG(tachypnea_count) AS avg_tachypnea_all,
    AVG(los_hours) AS avg_los_all,
    AVG(hospital_expire_flag) AS avg_mortality_all
  FROM all_metrics
)
SELECT 
  p.percentile_99,
  t.avg_tachycardia_top,
  t.avg_map_low_top,
  t.avg_tachypnea_top,
  t.avg_los_top,
  t.avg_mortality_top,
  a.avg_tachycardia_all,
  a.avg_map_low_all,
  a.avg_tachypnea_all,
  a.avg_los_all,
  a.avg_mortality_all
FROM percentiles p
CROSS JOIN top_quartile_metrics t
CROSS JOIN all_metrics_avg a;