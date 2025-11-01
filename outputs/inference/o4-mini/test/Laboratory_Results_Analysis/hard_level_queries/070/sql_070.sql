WITH hemorrhage_adms AS (
  -- 1. Identify hemorrhagic stroke admissions for male 40–50 y.o.
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
      ON d.icd_code = dicd.icd_code
         AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND d.icd_version = 9
    AND d.icd_code IN ('430','431','4320','4321','4329')
),
lab_abnorms AS (
  -- 2. Compute per-admission distinct abnormal labs in first 72h
  SELECT
    le.hadm_id,
    le.itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
      ON le.itemid = di.itemid
    JOIN hemorrhage_adms AS ha
      ON le.hadm_id = ha.hadm_id
  WHERE
    le.charttime BETWEEN ha.admittime
                      AND TIMESTAMP_ADD(ha.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND (
      le.valuenum < le.ref_range_lower
      OR le.valuenum > le.ref_range_upper
    )
  GROUP BY
    le.hadm_id,
    le.itemid
),
instability_scores AS (
  -- 3. Count unique abnormal labs
  SELECT
    ha.hadm_id,
    COUNT(ab.itemid) AS instability_score
  FROM
    hemorrhage_adms AS ha
    LEFT JOIN lab_abnorms AS ab
      ON ha.hadm_id = ab.hadm_id
  GROUP BY
    ha.hadm_id
),
quartiled AS (
  -- 4. Assign quartiles
  SELECT
    ha.hadm_id,
    ha.admittime,
    ha.dischtime,
    ha.los,
    ha.hospital_expire_flag,
    isco.instability_score,
    NTILE(4) OVER (ORDER BY isco.instability_score) AS instability_quartile
  FROM
    hemorrhage_adms AS ha
    JOIN instability_scores AS isco
      ON ha.hadm_id = isco.hadm_id
),
quartile_summary AS (
  -- 5. Summarize outcomes per quartile
  SELECT
    instability_quartile,
    COUNT(*) AS admissions_n,
    AVG(los) AS avg_los_days,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(instability_score) AS avg_instability
  FROM
    quartiled
  GROUP BY
    instability_quartile
),
general_lab_rates AS (
  -- 6. Precompute general inpatient lab abnormal rates
  WITH adult_adms AS (
    SELECT
      a.hadm_id,
      a.admittime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    WHERE
      p.anchor_age >= 18
  ),
  gen_abnorm AS (
    SELECT
      le.hadm_id,
      le.itemid
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
        ON le.itemid = di.itemid
      JOIN adult_adms AS aa
        ON le.hadm_id = aa.hadm_id
    WHERE
      le.charttime BETWEEN aa.admittime
                        AND TIMESTAMP_ADD(aa.admittime, INTERVAL 72 HOUR)
      AND le.valuenum IS NOT NULL
      AND (
        le.valuenum < le.ref_range_lower
        OR le.valuenum > le.ref_range_upper
      )
    GROUP BY
      le.hadm_id,
      le.itemid
  )
  SELECT
    itemid,
    COUNT(*) * 1.0 / COUNT(DISTINCT hadm_id) OVER () AS general_abnormal_rate
  FROM
    gen_abnorm
  GROUP BY
    itemid
)

-- Final output: quartile summary
SELECT
  qs.instability_quartile,
  qs.admissions_n,
  qs.avg_los_days,
  qs.mortality_rate,
  qs.avg_instability
FROM
  quartile_summary AS qs
ORDER BY
  qs.instability_quartile;