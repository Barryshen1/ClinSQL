WITH aki_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 52 AND 62
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      WHERE dx.subject_id = adm.subject_id
        AND dx.hadm_id = adm.hadm_id
        AND (
          (dx.icd_version = 9 AND dx.icd_code LIKE '584%')
          OR (dx.icd_version = 10 AND dx.icd_code LIKE 'N17%')
        )
    )
),
readmission_flags AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    CASE
      WHEN TIMESTAMP_DIFF(MIN(next.admittime), a.dischtime, DAY) <= 30
        THEN 1
      ELSE 0
    END AS readmit_30d
  FROM aki_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next
    ON a.subject_id = next.subject_id
    AND next.admittime > a.dischtime
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime
)
SELECT
  STDDEV_POP(readmit_30d) AS stddev_readmit_30d
FROM readmission_flags;