WITH
  -- Define the target population: 86-year-old man with pulmonary embolism and high comorbidity
  target_population AS (
    SELECT
      p.subject_id,
      p.gender,
      p.anchor_age,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      d.icd_code,
      d.icd_version,
      d.seq_num
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
      JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON a.hadm_id = d.hadm_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age = 86
      AND d.icd_code = 'I26.9' -- Pulmonary embolism code
      AND d.seq_num = 1 -- Assuming the primary diagnosis is the first one
  ),
  -- Calculate comorbidity risk score for each patient
  comorbidity_scores AS (
    SELECT
      tp.subject_id,
      tp.hadm_id,
      -- Calculate a simplified comorbidity score (e.g., number of diagnoses)
      -- A more sophisticated score like Charlson Comorbidity Index would require more complex logic
      COUNT(DISTINCT d.icd_code) AS comorbidity_score
    FROM
      target_population AS tp
      JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON tp.hadm_id = d.hadm_id
    GROUP BY
      tp.subject_id,
      tp.hadm_id
  ),
  -- Filter for patients with high comorbidity (risk score > 75th percentile)
  high_comorbidity_population AS (
    SELECT
      cs.subject_id,
      cs.hadm_id,
      cs.comorbidity_score
    FROM
      comorbidity_scores AS cs
    WHERE
      cs.comorbidity_score > (
        SELECT
          PERCENTILE_CONT(0.75, ARRAY(SELECT comorbidity_score FROM comorbidity_scores))
      )
  ),
  -- Calculate 90-day mortality
  mortality AS (
    SELECT
      hcp.subject_id,
      hcp.hadm_id,
      CASE
        WHEN p.dod BETWEEN a.dischtime AND DATE_ADD(a.dischtime, INTERVAL 90 DAY) THEN 1
        ELSE 0
      END AS mortality_90_day
    FROM
      high_comorbidity_population AS hcp
      JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON hcp.hadm_id = a.hadm_id
      JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON hcp.subject_id = p.subject_id
    WHERE
      p.dod IS NOT NULL
  ),
  -- Calculate mean risk score and 9;