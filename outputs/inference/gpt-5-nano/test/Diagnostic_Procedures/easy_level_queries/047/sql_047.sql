WITH eligible_hadm AS (
  -- All hospitalizations for male patients aged 37-47 at admission
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 37 AND 47
    AND p.gender = 'M'
  GROUP BY a.hadm_id
),
ablation_counts AS (
  -- Per-hadm_id count of distinct ablation/cardioversion procedures
  SELECT a.hadm_id, COUNT(DISTINCT pi.icd_code) AS cnt
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
    ON a.hadm_id = pi.hadm_id AND a.subject_id = pi.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON pi.icd_code = d.icd_code AND pi.icd_version = d.icd_version
  WHERE
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 37 AND 47
    AND p.gender = 'M'
    AND (LOWER(d.long_title) LIKE '%ablation%' OR LOWER(d.long_title) LIKE '%cardioversion%')
  GROUP BY a.hadm_id
)
SELECT
  STDDEV_SAMP(COALESCE(ac.cnt, 0)) AS sd_distinct_ablation_or_cardioversion
FROM eligible_hadm h
LEFT JOIN ablation_counts ac
  ON h.hadm_id = ac.hadm_id;