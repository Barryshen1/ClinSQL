WITH
  base_admissions AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag,
      EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
      p.gender
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    WHERE
      p.gender = 'F'
      AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 59 AND 69
  ),
  pe_diagnoses AS (
    SELECT
      d.subject_id,
      d.hadm_id,
      d.icd_code
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE
      dd.long_title LIKE '%pulmonary embolism%'
  ),
  pe_cohort AS (
    SELECT
      ba.*
    FROM
      base_admissions ba
    INNER JOIN
      pe_diagnoses pd
      ON ba.subject_id = pd.subject_id AND ba.hadm_id = pd.hadm_id
  ),
  cci_scores AS (
    SELECT
      d.subject_id,
      d.hadm_id,
      COUNT(DISTINCT CASE WHEN d.icd_code NOT IN (SELECT icd_code FROM pe_diagnoses) THEN d.icd_code END) AS cci_proxy
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE
      d.hadm_id IN (SELECT hadm_id FROM base_admissions)
    GROUP BY
      d.subject_id, d.hadm_id
  ),
  high_comorbidity_pe AS (
    SELECT
      pc.*,
      cs.cci_proxy
    FROM
      pe_cohort pc
    INNER JOIN
      cci_scores cs
      ON pc.subject_id = cs.subject_id AND pc.hadm_id = cs.hadm_id
    WHERE
      cs.cci_proxy >= 3
  ),
  pe_mortality AS (
    SELECT
      subject_id,
      hadm_id,
      CASE
        WHEN deathtime IS NOT NULL AND deathtime <= dischtime + INTERVAL 30 DAY THEN 1
        ELSE 0
      END AS died_30day
    FROM
      high_comorbidity_pe
  ),
  cardio_complications AS (
    SELECT
      d.subject_id,
      d.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE
      dd.long_title LIKE '%myocardial infarction%'
  ),
  neuro_complications AS (
    SELECT
      d.subject_id,
      d.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE
      dd.long_title LIKE '%stroke%'
  ),
  pe_survivors AS (
    SELECT
      hcp.subject_id,
      hcp.hadm_id,
      DATEDIFF(hcp.dischtime, hcp.admittime) AS los
    FROM
      high_comorbidity_pe hcp
    INNER JOIN
      pe_mortality pm
      ON hcp.subject_id = pm.subject_id AND hcp.hadm_id = pm.hadm_id
    WHERE
      pm.died_30day = 0
  ),
  pe_metrics AS (
    SELECT
      AVG(cci_proxy) AS mean_cci,
      AVG(pm.died_30day) AS mortality_30day,
      AVG(CASE WHEN cc.subject_id IS NOT NULL THEN 1 ELSE 0 END) AS cardio_complication_rate,
      AVG(CASE WHEN nc.subject_id IS NOT NULL THEN 1 ELSE 0 END) AS neuro_complication_rate,
      AVG(ps.los) AS mean_los_survivors
    FROM
      high_comorbidity_pe hcp
    LEFT JOIN
      pe_mortality pm
      ON hcp.subject_id = pm.subject_id AND hcp.hadm_id = pm.hadm_id
    LEFT JOIN
      cardio_complications cc
      ON hcp.subject_id = cc.subject_id AND hcp.hadm_id = cc.hadm_id
    LEFT JOIN
      neuro_complications nc
      ON hcp.subject_id = nc.subject_id AND hcp.hadm_id = nc.hadm_id
    LEFT JOIN
      pe_survivors ps
      ON hcp.subject_id = ps.subject_id AND hcp.hadm_id = ps.hadm_id
  ),
  general_cohort AS (
    SELECT
      ba.*,
      cs.cci_proxy
    FROM
      base_admissions ba
    LEFT JOIN
      cci_scores cs
      ON ba.subject_id = cs.subject_id AND ba.hadm_id = cs.hadm_id
    WHERE
      NOT EXISTS (
        SELECT 1
        FROM pe_diagnoses pd
        WHERE pd.subject_id = ba.subject_id AND pd.hadm_id = ba.hadm_id
      )
  ),
  general_mortality AS (
    SELECT
      subject_id,
      hadm_id,
      CASE
        WHEN deathtime IS NOT NULL AND deathtime <= dischtime + INTERVAL 30 DAY THEN 1
        ELSE 0
      END AS died_30day
    FROM
      general_cohort
  ),
  general_cardio AS (
    SELECT
      d.subject_id,
      d.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE
      dd.long_title LIKE '%myocardial infarction%'
      AND d.hadm_id IN (SELECT hadm_id FROM general_cohort)
  ),
  general_neuro AS (
    SELECT
      d.subject_id,
      d.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE
      dd.long_title LIKE '%stroke%'
      AND d.hadm_id IN (SELECT hadm_id FROM general_cohort)
  ),
  general_survivors AS (
    SELECT
      gc.subject_id,
      gc.hadm_id,
      DATEDIFF(gc.dischtime, gc.admittime) AS los
    FROM
      general_cohort gc
    INNER JOIN
      general_mortality gm
      ON gc.subject_id = gm.subject_id AND gc.hadm_id = gm.hadm_id
    WHERE
      gm.died_30day = 0
  ),
  general_metrics AS (
    SELECT
      AVG(cci_proxy) AS mean_cci,
      AVG(gm.died_30day) AS mortality_30day,
      AVG(CASE WHEN cc.subject_id IS NOT NULL THEN 1 ELSE 0 END) AS cardio_complication_rate,
      AVG(CASE WHEN nc.subject_id IS NOT NULL THEN 1 ELSE 0 END) AS neuro_complication_rate,
      AVG(gs.los) AS mean_los_survivors
    FROM
      general_cohort gc
    LEFT JOIN
      general_mortality gm
      ON gc.subject_id = gm.subject_id AND gc.hadm_id = gm.hadm_id
    LEFT JOIN
      general_cardio cc
      ON gc.subject_id = cc.subject_id AND gc.hadm_id = cc.hadm_id
    LEFT JOIN
      general_neuro nc
      ON gc.subject_id = nc.subject_id AND gc.hadm_id = nc.hadm_id
    LEFT JOIN
      general_survivors gs
      ON gc.subject_id = gs.subject_id AND gc.hadm_id = gs.hadm_id
  ),
  general_cci AS (
    SELECT
      cci_proxy
    FROM
      general_cohort
    WHERE
      cci_proxy IS NOT NULL
  ),
  pe_percentile AS (
    SELECT
      hcp.subject_id,
      hcp.hadm_id,
      hcp.cci_proxy,
      (SELECT 
          COUNT(*) * 1.0 / (SELECT COUNT(*) FROM general_cci) 
        FROM general_cci gc 
        WHERE gc.cci_proxy <= hcp.cci_proxy
      ) AS cci_percentile
    FROM
      high_comorbidity_pe hcp
  ),
  pe_percentile_summary AS (
    SELECT
      APPROX_QUANTILES(cci_percentile, 100)[OFFSET(50)] AS median_percentile
    FROM
      pe_percentile
  )
SELECT
  pm.mean_cci AS pe_mean_cci,
  pm.mortality_30day AS pe_30day_mortality,
  pm.cardio_complication_rate AS pe_cardio_rate,
  pm.neuro_complication_rate AS pe_neuro_rate,
  pm.mean_los_survivors AS pe_mean_los_survivors,
  gm.mean_cci AS general_mean_cci,
  gm.mortality_30day AS general_30day_mortality,
  gm.cardio_complication_rate AS general_cardio_rate,
  gm.neuro_complication_rate AS general_neuro_rate,
  gm.mean_los_survivors AS general_mean_los_survivors,
  pps.median_percentile AS pe_cci_percentile
FROM
  pe_metrics pm,
  general_metrics gm,
  pe_percentile_summary pps;