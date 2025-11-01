WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag,
    a.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i ON p.subject_id = i.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON p.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND LOWER(did.long_title) LIKE '%cardiac arrest%'
    AND i.intime IS NOT NULL
),

lab_48h AS (
  SELECT
    c.stay_id,
    le.valuenum,
    le.charttime,
    di.ref_range_lower,
    di.ref_range_upper
  FROM cohort c
  INNER JOIN physionet-data.mimiciv_3_1_hosp.labevents le ON c.subject_id = le.subject_id AND c.hadm_id = le.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems di ON le.itemid = di.itemid
  WHERE le.charttime >= c.intime
    AND le.charttime <= TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    AND le.valuenum IS NOT NULL
    AND di.ref_range_lower IS NOT NULL
    AND di.ref_range_upper IS NOT NULL
),

lab_instability AS (
  SELECT
    stay_id,
    STDDEV(valuenum) AS lab_instability_score
  FROM lab_48h
  GROUP BY stay_id
  HAVING STDDEV(valuenum) IS NOT NULL
),

p90 AS (
  SELECT PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY lab_instability_score) AS p90_score
  FROM lab_instability
),

high_instability AS (
  SELECT
    li.stay_id,
    li.lab_instability_score,
    c.hospital_expire_flag,
    c.los
  FROM lab_instability li
  INNER JOIN cohort c ON li.stay_id = c.stay_id
  CROSS JOIN p90
  WHERE li.lab_instability_score >= p90.p90_score
),

critical_labs_all AS (
  SELECT
    c.stay_id,
    COUNT(*) AS critical_lab_count
  FROM cohort c
  INNER JOIN lab_48h l ON c.stay_id = l.stay_id
  WHERE l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper
  GROUP BY c.stay_id
),

critical_labs_high AS (
  SELECT
    hi.stay_id,
    cla.critical_lab_count
  FROM high_instability hi
  INNER JOIN critical_labs_all cla ON hi.stay_id = cla.stay_id
)

SELECT
  COUNT(*) AS count_high_instability,
  SUM(hi.hospital_expire_flag) AS mortality_high_instability,
  AVG(hi.los) AS mean_los_high_instability,
  AVG(clh.critical_lab_count) AS mean_critical_labs_high_instability,
  (SELECT AVG(cla.critical_lab_count) FROM critical_labs_all cla) AS mean_critical_labs_all_cohort
FROM high_instability hi
LEFT JOIN critical_labs_high clh ON hi.stay_id = clh.stay_id;