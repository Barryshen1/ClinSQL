WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (
      PARTITION BY p.subject_id
      ORDER BY a.admittime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.insurance = 'Medicare'
    AND UPPER(a.admission_location) LIKE 'EMERGENCY%'
    AND d.seq_num = 1
    AND (
         (d.icd_version = 9 AND d.icd_code LIKE '560%')
         OR (d.icd_version = 10 AND d.icd_code LIKE 'K56%')
        )
    AND a.dischtime IS NOT NULL
)
SELECT COUNT(*) AS num_index_admissions
FROM cohort
WHERE rn = 1;