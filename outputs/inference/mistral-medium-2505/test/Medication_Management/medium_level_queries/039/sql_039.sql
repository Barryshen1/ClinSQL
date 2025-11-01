WITH
-- Get patients with T2DM and heart failure
t2dm_hf_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.hadm_id IN (
      -- Patients with T2DM (E11.* codes)
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'E11%'
    )
    AND a.hadm_id IN (
      -- Patients with heart failure (I50.* codes)
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'I50%'
    )
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48 -- At least 48h stay
),

-- GLP-1 medications (common injectable ones)
glp1_meds AS (
  SELECT DISTINCT
    subject_id,
    hadm_id,
    CASE
      WHEN LOWER(drug) LIKE '%exenatide%'
           OR LOWER(drug) LIKE '%byetta%'
           OR LOWER(drug) LIKE '%bydureon%'
           OR LOWER(drug) LIKE '%liraglutide%'
           OR LOWER(drug) LIKE '%victoza%'
           OR LOWER(drug) LIKE '%saxenda%'
           OR LOWER(drug) LIKE '%dulaglutide%'
           OR LOWER(drug) LIKE '%trulicity%'
           OR LOWER(drug) LIKE '%semaglutide%'
           OR LOWER(drug) LIKE '%ozempic%'
           OR LOWER(drug) LIKE '%wegovy%'
           OR LOWER(drug) LIKE '%lixisenatide%'
           OR LOWER(drug) LIKE '%adlyxin%'
      THEN TRUE
      ELSE FALSE
    END AS is_glp1
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) LIKE '%exenatide%'
    OR LOWER(drug) LIKE '%byetta%'
    OR LOWER(drug) LIKE '%bydureon%'
    OR LOWER(drug) LIKE '%liraglutide%'
    OR LOWER(drug) LIKE '%victoza%'
    OR LOWER(drug) LIKE '%saxenda%'
    OR LOWER(drug) LIKE '%dulaglutide%'
    OR LOWER(drug) LIKE '%trulicity%'
    OR LOWER(drug) LIKE '%semaglutide%'
    OR LOWER(drug) LIKE '%ozempic%'
    OR LOWER(drug) LIKE '%wegovy%'
    OR LOWER(drug) LIKE '%lixisenatide%'
    OR LOWER(drug) LIKE '%adlyxin%'
),

-- GLP-1 prescriptions in first 24h
first_24h_glp1 AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    MAX(g.is_glp1) AS has_glp1
  FROM
    t2dm_hf_patients p
  JOIN
    glp1_meds g
    ON p.subject_id = g.subject_id AND p.hadm_id = g.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.subject_id = pr.subject_id AND p.hadm_id = pr.hadm_id
  WHERE
    pr.starttime BETWEEN p.admittime AND TIMESTAMP_ADD(p.admittime, INTERVAL 24 HOUR)
  GROUP BY
    p.subject_id, p.hadm_id
),

-- GLP-1 prescriptions in final 48h
final_48h_glp1 AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    MAX(g.is_glp1) AS has_glp1
  FROM
    t2dm_hf_patients p
  JOIN
    glp1_meds g
    ON p.subject_id = g.subject_id AND p.hadm_id = g.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.subject_id = pr.subject_id AND p.hadm_id = pr.hadm_id
  WHERE
    pr.starttime BETWEEN TIMESTAMP_SUB(p.dischtime, INTERVAL 48 HOUR) AND p.dischtime
  GROUP BY
    p.subject_id, p.hadm_id
),

-- Counts for prevalence calculation
prevalence_counts AS (
  SELECT
    COUNT(DISTINCT p.subject_id) AS total_patients,
    COUNT(DISTINCT CASE WHEN f.has_glp1 THEN p.subject_id END) AS first_24h_glp1_count,
    COUNT(DISTINCT CASE WHEN l.has_glp1 THEN p.subject_id END) AS final_48h_glp1_count
  FROM
    t2dm_hf_patients p
  LEFT JOIN
    first_24h_glp1 f
    ON p.subject_id = f.subject_id AND p.hadm_id = f.hadm_id
  LEFT JOIN
    final_48h_glp1 l
    ON p.subject_id = l.subject_id AND p.hadm_id = l.hadm_id
)

-- Final results
SELECT
  total_patients,
  first_24h_glp1_count,
  ROUND((first_24h_glp1_count / total_patients) * 100, 2) AS first_24h_prevalence,
  final_48h_glp1_count,
  ROUND((final_48h_glp1_count / total_patients) * 100, 2) AS final_48h_prevalence,
  (final_48h_glp1_count - first_24h_glp1_count) AS absolute_change,
  ROUND(((final_48h_glp1_count - first_24h_glp1_count) / NULLIF(first_24h_glp1_count, 0)) * 100, 2) AS relative_change_percent
FROM
  prevalence_counts;