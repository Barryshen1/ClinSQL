WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING(subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
      USING(subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di1
      ON d1.icd_code = di1.icd_code
      AND d1.icd_version = di1.icd_version
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      USING(subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di2
      ON d2.icd_code = di2.icd_code
      AND d2.icd_version = di2.icd_version
  WHERE
    p.anchor_age BETWEEN 77 AND 87
    AND LOWER(di1.long_title) LIKE '%diabetes%'
    AND LOWER(di2.long_title) LIKE '%heart failure%'
),
meds AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.drug) IN ('metformin','glipizide','glyburide','pioglitazone','sitagliptin') THEN 'Oral'
      ELSE NULL
    END AS agent_type,
    p.starttime,
    a.admittime,
    a.dischtime
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON c.subject_id = p.subject_id
      AND c.hadm_id = p.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON c.subject_id = a.subject_id
      AND c.hadm_id = a.hadm_id
  WHERE
    LOWER(p.drug) LIKE '%insulin%'
    OR LOWER(p.drug) IN ('metformin','glipizide','glyburide','pioglitazone','sitagliptin')
),
window_flags AS (
  SELECT
    subject_id,
    hadm_id,
    agent_type,
    MAX(CASE WHEN starttime <= TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS first48,
    MAX(CASE WHEN starttime >= TIMESTAMP_SUB(dischtime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS final72
  FROM
    meds
  GROUP BY
    subject_id,
    hadm_id,
    agent_type
),
final AS (
  SELECT
    agent_type,
    AVG(first48) AS rate_first48,
    AVG(final72) AS rate_final72,
    (AVG(final72) - AVG(first48)) * 100 AS net_change_pp
  FROM
    window_flags
  GROUP BY
    agent_type
)
SELECT
  *
FROM
  final;