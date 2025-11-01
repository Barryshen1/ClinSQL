WITH pancreatitis_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE (p.gender = 'F' OR LOWER(p.gender) = 'female')
    AND p.anchor_age BETWEEN 65 AND 75
    AND LOWER(dd.long_title) LIKE '%pancreatitis%'
),

-- Part 2: Lab events within first 48 hours for pancreatitis cohort
lab_events AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    e.charttime,
    e.valuenum,
    e.ref_range_lower,
    e.ref_range_upper,
    LOWER(IFNULL(e.flag, '')) AS flag
  FROM pancreatitis_cohort AS pc
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS e
    ON pc.subject_id = e.subject_id AND pc.hadm_id = e.hadm_id
  WHERE e.charttime >= pc.admittime
    AND e.charttime < TIMESTAMP_ADD(pc.admittime, INTERVAL 48 HOUR)
),

-- Part 3: Per-admission instability score and critical lab indicator
instability AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    pc.admittime,
    pc.dischtime,
    pc.hospital_expire_flag,
    pc.gender,
    pc.anchor_age,
    COALESCE(SUM(
      CASE
        WHEN le.valuenum IS NOT NULL
             AND (
                   (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
                   OR
                   (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
                 )
        THEN 1
        ELSE 0
      END
    ), 0) AS instability_score,
    MAX(
      CASE
        WHEN LOWER(le.flag) LIKE '%critical%'
        THEN 1
        ELSE 0
      END
    ) AS has_critical_lab
  FROM lab_events AS le
  JOIN pancreatitis_cohort AS pc
    ON le.subject_id = pc.subject_id AND le.hadm_id = pc.hadm_id
  GROUP BY le.subject_id, le.hadm_id, pc.admittime, pc.dischtime, pc.hospital_expire_flag, pc.gender, pc.anchor_age
),

-- Part 4: Assign quintiles based on instability_score
pancreatitis_quint AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.admittime,
    i.dischtime,
    i.hospital_expire_flag,
    i.gender,
    i.anchor_age,
    i.instability_score,
    i.has_critical_lab,
    NTILE(5) OVER (ORDER BY i.instability_score) AS quintile
  FROM instability AS i
),

-- Part 5: Age-matched inpatients (65-75, female) for baseline of critical labs
age_matched AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE (p.gender = 'F' OR LOWER(p.gender) = 'female')
    AND p.anchor_age BETWEEN 65 AND 75
),

age_matched_crit_pct AS (
  SELECT
    AVG(has_critical) AS age_matched_crit_pct
  FROM (
    SELECT
      am.subject_id,
      am.hadm_id,
      MAX(
        CASE
          WHEN LOWER(IFNULL(le.flag, '')) LIKE '%critical%'
          THEN 1
          ELSE 0
        END
      ) AS has_critical
    FROM age_matched AS am
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON am.subject_id = le.subject_id AND am.hadm_id = le.hadm_id
    WHERE le.charttime >= am.admittime
      AND le.charttime < TIMESTAMP_ADD(am.admittime, INTERVAL 48 HOUR)
    GROUP BY am.subject_id, am.hadm_id
  )
),

-- Part 6: Final aggregation by quintile
final AS (
  SELECT
    pq.quintile,
    COUNT(*) AS count_patients,
    AVG(pq.instability_score) AS mean_instability,
    AVG(TIMESTAMP_DIFF(pq.dischtime, pq.admittime, SECOND) / 86400.0) AS mean_los_days,
    AVG(CASE WHEN pq.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS mortality_rate,
    AVG(CASE WHEN pq.has_critical_lab = 1 THEN 1.0 ELSE 0.0 END) AS pct_critical_pancreatitis,
    (SELECT age_matched_crit_pct FROM age_matched_crit_pct) AS age_matched_crit_pct
  FROM pancreatitis_quint AS pq
  GROUP BY pq.quintile
  ORDER BY pq.quintile
)

SELECT * FROM final;