WITH resp_hadm AS (
  SELECT DISTINCT di.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS di
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS dic
    ON di.icd_code = dic.icd_code
   AND di.icd_version = dic.icd_version
  WHERE LOWER(dic.long_title) LIKE '%respiratory failure%'
),

-- Part 2: define the cohort (males, 40-50, ICU stays)
cohort AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag AS mortality_hosp,
    p.gender,
    p.anchor_age,
    CASE WHEN rh.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS resp_failure
  FROM physionet-data.mimiciv_3_1_icu.icustays AS i
  JOIN physionet-data.mimiciv_3_1_hosp.admissions AS a
    ON a.hadm_id = i.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.patients AS p
    ON p.subject_id = i.subject_id
  LEFT JOIN resp_hadm AS rh
    ON rh.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),

-- Part 3: extract vitals within first 48 hours and classify into four categories
vitals_window AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    CASE
      WHEN di.label LIKE '%Heart Rate%' OR di.label LIKE '%HR%' THEN 'HR'
      WHEN di.label LIKE '%Mean arterial pressure%' OR di.label LIKE '%MAP%' THEN 'MAP'
      WHEN di.label LIKE '%Respiratory Rate%' THEN 'RR'
      WHEN di.label LIKE '%O2 Saturation%' OR di.label LIKE '%SpO2%' THEN 'SpO2'
      ELSE NULL
    END AS vital_cat,
    ce.valuenum
  FROM cohort AS c
  JOIN physionet-data.mimiciv_3_1_icu.chartevents AS ce
    ON ce.hadm_id = c.hadm_id
   AND ce.stay_id = c.stay_id
  JOIN physionet-data.mimiciv_3_1_icu.d_items AS di
    ON ce.itemid = di.itemid
  WHERE ce.charttime >= c.intime
    AND ce.charttime <= TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    AND (
       di.label LIKE '%Heart Rate%' OR di.label LIKE '%HR%'
       OR di.label LIKE '%Mean arterial pressure%' OR di.label LIKE '%MAP%'
       OR di.label LIKE '%Respiratory Rate%'
       OR di.label LIKE '%O2 Saturation%' OR di.label LIKE '%SpO2%'
    )
),

-- Part 4: per-stay VII and burden calculations (within 0-48h window)
per_stay_metrics AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    c.resp_failure,
    c.los,
    c.mortality_hosp,
    SUM(
      CASE
        WHEN v.vital_cat = 'HR' AND (v.valuenum > 100 OR v.valuenum < 60) THEN 1
        WHEN v.vital_cat = 'MAP' AND v.valuenum < 65 THEN 1
        WHEN v.vital_cat = 'RR'  AND v.valuenum > 24 THEN 1
        WHEN v.vital_cat = 'SpO2' AND v.valuenum < 92 THEN 1
        ELSE 0
      END
    ) AS vii,
    SUM(
      CASE WHEN v.vital_cat = 'MAP' AND v.valuenum < 65 THEN 1 ELSE 0 END
    ) AS hypotensive_burden,
    SUM(
      CASE WHEN v.vital_cat = 'HR' AND v.valuenum > 100 THEN 1 ELSE 0 END
    ) AS tachycardic_burden
  FROM vitals_window AS v
  JOIN cohort AS c
    ON c.hadm_id = v.hadm_id
   AND c.stay_id = v.stay_id
  GROUP BY v.subject_id, v.hadm_id, v.stay_id, c.resp_failure, c.los, c.mortality_hosp
)

-- Part 5: aggregate by group (RespFailure vs Other)
SELECT
  CASE WHEN ps.resp_failure = 1 THEN 'Respiratory Failure' ELSE 'Other' END AS resp_group,
  (APPROX_QUANTILES(ps.vii, 100))[OFFSET(25)] AS vii_p25,
  (APPROX_QUANTILES(ps.vii, 100))[OFFSET(50)] AS vii_p50,
  (APPROX_QUANTILES(ps.vii, 100))[OFFSET(75)] AS vii_p75,
  (APPROX_QUANTILES(ps.vii, 100))[OFFSET(95)] AS vii_p95,
  STDDEV(ps.vii) AS vii_sd,
  AVG(ps.hypotensive_burden) AS mean_hypotensive_burden,
  AVG(ps.tachycardic_burden) AS mean_tachycardic_burden,
  AVG(ps.los) AS mean_los,
  (APPROX_QUANTILES(ps.los, 100))[OFFSET(50)] AS median_los,
  AVG(CASE WHEN ps.mortality_hosp = 1 THEN 1.0 ELSE 0.0 END) AS mortality_rate
FROM per_stay_metrics AS ps
GROUP BY CASE WHEN ps.resp_failure = 1 THEN 'Respiratory Failure' ELSE 'Other' END
ORDER BY resp_group;