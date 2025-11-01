WITH acute_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
      AND a.hadm_id    = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON d.icd_code    = dd.icd_code
      AND d.icd_version= dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 47 AND 57
    AND LOWER(dd.long_title) LIKE '%acute pancreatitis%'
),
proc_counts AS (
  SELECT
    aa.subject_id,
    aa.hadm_id,
    aa.los,
    SUM(
      CASE
        WHEN LOWER(dp.long_title) LIKE '%tomography%'
          OR LOWER(dp.long_title) LIKE '%magnetic resonance%'
        THEN 1
        ELSE 0
      END
    ) AS proc_count
  FROM
    acute_admissions AS aa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
      ON aa.hadm_id = pr.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dp
      ON pr.icd_code    = dp.icd_code
      AND pr.icd_version= dp.icd_version
  GROUP BY
    aa.subject_id,
    aa.hadm_id,
    aa.los
),
bucketed AS (
  SELECT
    subject_id,
    hadm_id,
    proc_count,
    CASE
      WHEN los BETWEEN 1 AND 4 THEN '1-4'
      WHEN los BETWEEN 5 AND 8 THEN '5-8'
      ELSE NULL
    END AS los_bucket
  FROM
    proc_counts
)
SELECT
  los_bucket,
  COUNT(DISTINCT subject_id)                                  AS patient_count,
  ROUND(AVG(proc_count), 2)                                   AS mean_CT_MRI_per_admission
FROM
  bucketed
WHERE
  los_bucket IS NOT NULL
GROUP BY
  los_bucket
ORDER BY
  los_bucket;