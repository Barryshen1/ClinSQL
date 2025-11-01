WITH charlson AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    SUM(
      CASE
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '410%') OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%') THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '428%') OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%') THEN 1
        WHEN (d.icd_version = 9 AND (d.icd_code LIKE '440%' OR d.icd_code = '443.9')) OR (d.icd_version = 10 AND (d.icd_code LIKE 'I70%' OR d.icd_code = 'I73.9')) THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '438') OR (d.icd_version = 10 AND d.icd_code LIKE 'I6%') THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '290%') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'F01' AND 'F03') THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '490' AND '496') OR (d.icd_version = 10 AND d.icd_code LIKE 'J4%') THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '710%') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'M05' AND 'M06') THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '531' AND '534') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'K25' AND 'K28') THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '570' AND '571') OR (d.icd_version = 10 AND d.icd_code LIKE 'K7%') THEN 1
        WHEN (d.icd_version = 9 AND (d.icd_code LIKE '250.0%' OR d.icd_code LIKE '250.1%' OR d.icd_code LIKE '250.2%' OR d.icd_code LIKE '250.3%')) OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10.0%' OR d.icd_code LIKE 'E10.1%' OR d.icd_code LIKE 'E10.2%' OR d.icd_code LIKE 'E10.3%' OR d.icd_code LIKE 'E11.0%' OR d.icd_code LIKE 'E11.1%' OR d.icd_code LIKE 'E11.2%' OR d.icd_code LIKE 'E11.3%' OR d.icd_code LIKE 'E12.0%' OR d.icd_code LIKE 'E12.1%' OR d.icd_code LIKE 'E12.2%' OR d.icd_code LIKE 'E12.3%' OR d.icd_code LIKE 'E13.0%' OR d.icd_code LIKE 'E13.1%' OR d.icd_code LIKE 'E13.2%' OR d.icd_code LIKE 'E13.3%' OR d.icd_code LIKE 'E14.0%' OR d.icd_code LIKE 'E14.1%' OR d.icd_code LIKE 'E14.2%' OR d.icd_code LIKE 'E14.3%')) THEN 1
        WHEN (d.icd_version = 9 AND (d.icd_code LIKE '250.4%' OR d.icd_code LIKE '250.5%' OR d.icd_code LIKE '250.6%' OR d.icd_code LIKE '250.7%' OR d.icd_code LIKE '250.8%' OR d.icd_code LIKE '250.9%')) OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10.4%' OR d.icd_code LIKE 'E10.5%' OR d.icd_code LIKE 'E10.6%' OR d.icd_code LIKE 'E10.7%' OR d.icd_code LIKE 'E10.8%' OR d.icd_code LIKE 'E10.9%' OR d.icd_code LIKE 'E11.4%' OR d.icd_code LIKE 'E11.5%' OR d.icd_code LIKE 'E11.6%' OR d.icd_code LIKE 'E11.7%' OR d.icd_code LIKE 'E11.8%' OR d.icd_code LIKE 'E11.9%' OR d.icd_code LIKE 'E12.4%' OR d.icd_code LIKE 'E12.5%' OR d.icd_code LIKE 'E12.6%' OR d.icd_code LIKE 'E12.7%' OR d.icd_code LIKE 'E12.8%' OR d.icd_code LIKE 'E12.9%' OR d.icd_code LIKE 'E13.4%' OR d.icd_code LIKE 'E13.5%' OR d.icd_code LIKE 'E13.6%' OR d.icd_code LIKE 'E13.7%' OR d.icd_code LIKE 'E13.8%' OR d.icd_code LIKE 'E13.9%' OR d.icd_code LIKE 'E14.4%' OR d.icd_code LIKE 'E14.5%' OR d.icd_code LIKE 'E14.6%' OR d.icd_code LIKE 'E14.7%' OR d.icd_code LIKE 'E14.8%' OR d.icd_code LIKE 'E14.9%')) THEN 2
        WHEN (d.icd_version = 9 AND (d.icd_code LIKE '342%' OR d.icd_code = '344.0')) OR (d.icd_version = 10 AND (d.icd_code LIKE 'G81%' OR d.icd_code LIKE 'G82%' OR d.icd_code LIKE 'G04.1%' OR d.icd_code LIKE 'G11.4%' OR d.icd_code LIKE 'G12.2%' OR d.icd_code LIKE 'G80.1%' OR d.icd_code LIKE 'G80.2%')) THEN 2
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '585' AND '586') OR (d.icd_version = 10 AND (d.icd_code LIKE 'N18%' OR d.icd_code LIKE 'N19%')) THEN 2
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '140' AND '172') OR (d.icd_version = 9 AND d.icd_code BETWEEN '174' AND '176') OR (d.icd_version = 9 AND d.icd_code BETWEEN '179' AND '195') OR (d.icd_version = 9 AND d.icd_code BETWEEN '200' AND '208') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'C00' AND 'C97') THEN 2
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '204' AND '208') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'C91' AND 'C95') THEN 2
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '200' AND '202') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'C81' AND 'C90') THEN 2
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '196' AND '199') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'C77' AND 'C80') THEN 6
        WHEN (d.icd_version = 9 AND d.icd_code = '042') OR (d.icd_version = 10 AND d.icd_code = 'B20') THEN 6
        ELSE 0
      END
    ) AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.subject_id, d.hadm_id
),
heart_failure AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '428%') OR (icd_version = 10 AND icd_code LIKE 'I50%')
)
SELECT
  CASE
    WHEN los BETWEEN 1 AND 3 THEN '1-3'
    WHEN los BETWEEN 4 AND 7 THEN '4-7'
    WHEN los >= 8 THEN '>=8'
  END AS los_category,
  CASE
    WHEN charlson_score <= 3 THEN '<=3'
    WHEN charlson_score BETWEEN 4 AND 5 THEN '4-5'
    WHEN charlson_score > 5 THEN '>5'
  END AS charlson_category,
  SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS mortality_pct,
  AVG(los) AS avg_los,
  COUNTIF(discharge_location IN ('HOME', 'HOME WITH HOME HEALTH CARE')) * 100.0 / COUNT(*) AS home_pct,
  COUNTIF(discharge_location = 'REHABILITATION') * 100.0 / COUNT(*) AS rehab_pct,
  COUNTIF(discharge_location IN ('SKILLED NURSING FACILITY', 'SNF')) * 100.0 / COUNT(*) AS snf_pct,
  COUNTIF(discharge_location = 'HOSPICE') * 100.0 / COUNT(*) AS hospice_pct
FROM (
  SELECT
    a.hospital_expire_flag,
    a.discharge_location,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    c.charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN heart_failure hf ON a.hadm_id = hf.hadm_id
  JOIN charlson c ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 53 AND 63
) subquery
GROUP BY los_category, charlson_category
ORDER BY los_category, charlson_category;