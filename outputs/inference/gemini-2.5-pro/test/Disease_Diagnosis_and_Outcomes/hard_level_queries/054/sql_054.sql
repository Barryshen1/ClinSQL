WITH
  -- Step 1: Create a base population of female patients aged 59-69
  base_admissions AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      p.dod,
      (p.anchor_age + DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR)) AS age_at_admission,
      DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
      CASE
        WHEN p.dod IS NOT NULL AND DATETIME_DIFF(p.dod, a.admittime, DAY) BETWEEN 0 AND 30
          THEN 1
        ELSE 0
      END AS mortality_30_day
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'F'
      AND (p.anchor_age + DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR)) BETWEEN 59 AND 69
  ),
  -- Step 2: Map all ICD codes to Charlson comorbidity conditions for each admission
  charlson_components AS (
    SELECT
      hadm_id,
      -- For each hadm_id, flag if any of the diagnoses fall into a category
      MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('410', '412'))
                 OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('I21', 'I22') OR SUBSTR(icd_code, 1, 4) = 'I252') THEN 1 ELSE 0 END) AS mi,
      MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 5) = '39891' OR SUBSTR(icd_code, 1, 5) IN ('40201', '40211', '40291') OR SUBSTR(icd_code, 1, 5) IN ('40401', '40403', '40411', '40413', '40491', '40493') OR SUBSTR(icd_code, 1, 3) = '428' OR SUBSTR(icd_code, 1, 4) IN ('4254', '4255', '4257', '4258', '4259'))
                 OR icd_version = 10 AND (SUBSTR(icd_code, 1, 4) IN ('I099', 'I110', 'I130', 'I132', 'I255', 'I420', 'I425', 'I426', 'I427', 'I428', 'I429', 'I50') OR SUBSTR(icd_code, 1, 3) IN ('I43') OR SUBSTR(icd_code, 1, 4) = 'P290') THEN 1 ELSE 0 END) AS chf,
      MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('440', '441') OR SUBSTR(icd_code, 1, 4) IN ('4439', '4471', '5571', '5579'))
                 OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('I70', 'I71') OR SUBSTR(icd_code, 1, 4) IN ('I739', 'I771', 'K551', 'K558', 'K559')) THEN 1 ELSE 0 END) AS pvd,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '430' AND '438'
                 OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('G45', 'G46') OR SUBSTR(icd_code, 1, 3) BETWEEN 'I60' AND 'I69') THEN 1 ELSE 0 END) AS cevd,
      MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) = '290' OR SUBSTR(icd_code, 1, 4) = '2941' OR SUBSTR(icd_code, 1, 4) = '3312')
                 OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('F00', 'F01', 'F02', 'F03', 'G30') OR SUBSTR(icd_code, 1, 4) = 'F051' OR SUBSTR(icd_code, 1, 4) = 'G311') THEN 1 ELSE 0 END) AS dementia,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '490' AND '505'
                 OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) BETWEEN 'J40' AND 'J47' OR SUBSTR(icd_code, 1, 3) BETWEEN 'J60' AND 'J67') THEN 1 ELSE 0 END) AS cpd,
      MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 4) IN ('7100', '7101', '7102', '7103', '7104') OR SUBSTR(icd_code, 1, 4) IN ('7140', '7141', '7142') OR SUBSTR(icd_code, 1, 3) = '725')
                 OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('M05', 'M06', 'M32', 'M33', 'M34') OR SUBSTR(icd_code, 1, 4) = 'M315' OR SUBSTR(icd_code, 1, 4) = 'M351' OR SUBSTR(icd_code, 1, 4) = 'M353' OR SUBSTR(icd_code, 1, 4) = 'M360') THEN 1 ELSE 0 END) AS rheumd,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '531' AND '534'
                 OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'K25' AND 'K28' THEN 1 ELSE 0 END) AS pud,
      MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 4) IN ('5712', '5715', '5716'))
                 OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('B18', 'K73', 'K74') OR SUBSTR(icd_code, 1, 4) IN ('K700','K701','K702','K703','K709','K713','K714','K715','K717','K760')) THEN 1 ELSE 0 END) AS mld,
      MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 4) IN ('2500', '2501', '2502', '2503'))
                 OR icd_version = 10 AND (SUBSTR(icd_code, 1, 4) IN ('E100', 'E101', 'E109', 'E110', 'E111', 'E119')) THEN 1 ELSE 0 END) AS diab,
      MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 4) IN ('2504', '2505', '2506', '2507', '2508', '2509'))
                 OR icd_version = 10 AND (SUBSTR(icd_code, 1, 4) IN ('E102', 'E103', 'E104', 'E105', 'E107', 'E112', 'E113', 'E114', 'E115', 'E117')) THEN 1 ELSE 0 END) AS diab_comp,
      MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('342', '343') OR SUBSTR(icd_code, 1, 4) = '3341' OR SUBSTR(icd_code, 1, 4) BETWEEN '3440' AND '3446' OR SUBSTR(icd_code, 1, 4) = '3449')
                 OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('G81', 'G82') OR SUBSTR(icd_code, 1, 4) IN ('G041', 'G114', 'G801', 'G802', 'G830', 'G831', 'G832', 'G833', 'G834', 'G839')) THEN 1 ELSE 0 END) AS paraplegia,
      MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('582', '585', '586') OR SUBSTR(icd_code, 1, 4) IN ('5830', '5831', '5832', '5833', '5834', '5835', '5836', '5837') OR SUBSTR(icd_code, 1, 5) IN ('40301', '40311', '40391', '40402', '40412', '40492'))
                 OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('N18', 'N19') OR SUBSTR(icd_code, 1, 4) IN ('I120', 'I131')) THEN 1 ELSE 0 END) AS rend,
      MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) BETWEEN '140' AND '172' OR SUBSTR(icd_code, 1, 3) BETWEEN '174' AND '195' OR SUBSTR(icd_code, 1, 3) BETWEEN '200' AND '208')
                 OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) BETWEEN 'C00' AND 'C26' OR SUBSTR(icd_code, 1, 3) BETWEEN 'C30' AND 'C41' OR SUBSTR(icd_code, 1, 3) = 'C43' OR SUBSTR(icd_code, 1, 3) BETWEEN 'C45' AND 'C76' OR SUBSTR(icd_code, 1, 3) BETWEEN 'C81' AND 'C96') THEN 1 ELSE 0 END) AS malig,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) = '5722' OR SUBSTR(icd_code, 1, 4) = '5723' OR SUBSTR(icd_code, 1, 4) = '5724'
                 OR icd_version = 10 AND (SUBSTR(icd_code, 1, 4) IN ('I850', 'I859', 'I864', 'I982', 'K704', 'K711', 'K721', 'K729', 'K765', 'K766', 'K767')) THEN 1 ELSE 0 END) AS sld,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '196' AND '199'
                 OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'C77' AND 'C80' THEN 1 ELSE 0 END) AS mets,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '042'
                 OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('B20', 'B21', 'B22', 'B24') THEN 1 ELSE 0 END) AS aids
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY
      hadm_id
  ),
  -- Step 3: Calculate the final Charlson score from the components, respecting hierarchies
  charlson_scores AS (
    SELECT
      hadm_id,
      (
        mi + chf + pvd + cevd + dementia + cpd + rheumd + pud + paraplegia
        + (1 - sld) * mld -- if severe liver disease, mild doesn't count
        + (1 - diab_comp) * diab -- if diabetes w/ complication, simple diabetes doesn't count
        + 2 * diab_comp
        + 2 * rend
        + 3 * sld
        + (1 - mets) * 2 * malig -- if metastatic, local malignancy doesn't count
        + 6 * mets
        + 6 * aids
      ) AS charlson_score
    FROM
      charlson_components
  ),
  -- Step 4: Create flags for PE diagnosis and key complications
  hadm_flags AS (
    SELECT
      hadm_id,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) = '4151'
                 OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I26' THEN 1 ELSE 0 END) AS is_pe,
      MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) = '410' OR SUBSTR(icd_code, 1, 4) = '785.51' OR SUBSTR(icd_code, 1, 3) = '4275'))
                 OR (icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('I21', 'I22', 'I46') OR SUBSTR(icd_code, 1, 4) = 'R57.0'))
                 THEN 1 ELSE 0 END) AS has_cardio_comp,
      MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('430', '431', '432', '436') OR SUBSTR(icd_code, 1, 4) LIKE '433%' OR SUBSTR(icd_code, 1, 4) LIKE '434%'))
                 OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62', 'I63'))
                 THEN 1 ELSE 0 END) AS has_neuro_comp
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY
      hadm_id
  ),
  -- Step 5: Combine all data and define final Case/Control cohorts
  cohort_data AS (
    SELECT
      b.hadm_id,
      b.los_days,
      b.mortality_30_day,
      COALESCE(cs.charlson_score, 0) AS charlson_score,
      COALESCE(hf.is_pe, 0) AS is_pe,
      COALESCE(hf.has_cardio_comp, 0) AS has_cardio_comp,
      COALESCE(hf.has_neuro_comp, 0) AS has_neuro_comp,
      CASE
        WHEN COALESCE(hf.is_pe, 0) = 1 AND COALESCE(cs.charlson_score, 0) >= 5
          THEN 'Case'
        WHEN COALESCE(hf.is_pe, 0) = 0
          THEN 'Control'
        ELSE NULL
      END AS cohort_group
    FROM
      base_admissions AS b
    LEFT JOIN
      charlson_scores AS cs
      ON b.hadm_id = cs.hadm_id
    LEFT JOIN
      hadm_flags AS hf
      ON b.hadm_id = hf.hadm_id
  ),
  -- Step 6a: Calculate summary stats for the Case group
  case_summary AS (
    SELECT
      AVG(charlson_score) AS mean_comorbidity_risk_score,
      AVG(mortality_30_day) AS mortality_30_day_rate,
      AVG(has_cardio_comp) AS case_cardio_comp_rate,
      AVG(has_neuro_comp) AS case_neuro_comp_rate,
      AVG(IF(mortality_30_day = 0, los_days, NULL)) AS case_survivor_los
    FROM
      cohort_data
    WHERE
      cohort_group = 'Case'
  ),
  -- Step 6b: Calculate summary stats for the Control group
  control_summary AS (
    SELECT
      AVG(has_cardio_comp) AS control_cardio_comp_rate,
      AVG(has_neuro_comp) AS control_neuro_comp_rate,
      AVG(IF(mortality_30_day = 0, los_days, NULL)) AS control_survivor_los
    FROM
      cohort_data
    WHERE
      cohort_group = 'Control'
  ),
  -- Step 6c: Calculate the percentile of the case group's average score within the control group's distribution
  percentile_summary AS (
    WITH
      case_avg_score AS (
        SELECT
          AVG(charlson_score) AS avg_score
        FROM
          cohort_data
        WHERE
          cohort_group = 'Case'
      )
    SELECT
      SAFE_DIVIDE(
        (SELECT COUNT(*) FROM cohort_data WHERE cohort_group = 'Control' AND charlson_score < s.avg_score),
        (SELECT COUNT(*) FROM cohort_data WHERE cohort_group = 'Control')
      ) AS matched_profile_percentile
    FROM
      case_avg_score AS s
  )
-- Step 7: Combine all summary metrics into a single output table
SELECT
  -- Case Group Metrics
  cs.mean_comorbidity_risk_score,
  cs.mortality_30_day_rate,
  -- Comparative Metrics
  cs.case_cardio_comp_rate,
  ctrl.control_cardio_comp_rate,
  cs.case_neuro_comp_rate,
  ctrl.control_neuro_comp_rate,
  cs.case_survivor_los,
  ctrl.control_survivor_los,
  -- Percentile Metric
  ps.matched_profile_percentile
FROM
  case_summary AS cs,
  control_summary AS ctrl,
  percentile_summary AS ps;