SELECT
  AVG(DATE_DIFF(adm.dischtime, adm.admittime, DAY)) AS avg_length_of_stay
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON adm.subject_id = pat.subject_id
INNER JOIN (
  -- Get primary diagnosis via JOIN instead of multi-column IN
  SELECT
    d1.hadm_id,
    d1.icd_code,
    d1.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
  INNER JOIN (
    SELECT
      hadm_id,
      MIN(seq_num) AS min_seq
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY
      hadm_id
  ) d2
  ON d1.hadm_id = d2.hadm_id AND d1.seq_num = d2.min_seq
) dx
ON
  adm.hadm_id = dx.hadm_id
WHERE
  pat.gender = 'F'
  AND ( -- Age at admission: 61–71
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)
  ) BETWEEN 61 AND 71
  AND ( -- Heart failure codes (ICD-9: 428*, ICD-10: I50*)
    (dx.icd_version = 9 AND dx.icd_code LIKE '428%')
    OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%')
  );