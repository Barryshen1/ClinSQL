WITH target_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.dischtime - a.admittime >= INTERVAL 36 HOUR
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(di.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(di.long_title) LIKE '%acute heart failure%'
    )
)
SELECT
  AVG(CASE WHEN (
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      WHERE p.hadm_id = ta.hadm_id
        AND (
          LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%byetta%' OR LOWER(p.drug) LIKE '%bydureon%' OR
          LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%victoza%' OR
          LOWER(p.drug) LIKE '%semaglutide%' OR LOWER(p.drug) LIKE '%ozempic%' OR
          LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%trulicity%' OR
          LOWER(p.drug) LIKE '%albiglutide%' OR LOWER(p.drug) LIKE '%tanzeum%' OR
          LOWER(p.drug) LIKE '%lixisenatide%' OR LOWER(p.drug) LIKE '%adlyxin%'
        )
        AND (
          LOWER(p.route) LIKE '%subcut%' OR LOWER(p.route) LIKE '%sc%' OR LOWER(p.route) LIKE '%sq%' OR LOWER(p.route) LIKE '%inject%'
        )
        AND p.starttime BETWEEN ta.admittime AND ta.admittime + INTERVAL 24 HOUR
    )
    OR EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
      WHERE ph.hadm_id = ta.hadm_id
        AND (
          LOWER(ph.medication) LIKE '%exenatide%' OR LOWER(ph.medication) LIKE '%byetta%' OR LOWER(ph.medication) LIKE '%bydureon%' OR
          LOWER(ph.medication) LIKE '%liraglutide%' OR LOWER(ph.medication) LIKE '%victoza%' OR
          LOWER(ph.medication) LIKE '%semaglutide%' OR LOWER(ph.medication) LIKE '%ozempic%' OR
          LOWER(ph.medication) LIKE '%dulaglutide%' OR LOWER(ph.medication) LIKE '%trulicity%' OR
          LOWER(ph.medication) LIKE '%albiglutide%' OR LOWER(ph.medication) LIKE '%tanzeum%' OR
          LOWER(ph.medication) LIKE '%lixisenatide%' OR LOWER(ph.medication) LIKE '%adlyxin%'
        )
        AND (
          LOWER(ph.route) LIKE '%subcut%' OR LOWER(ph.route) LIKE '%sc%' OR LOWER(ph.route) LIKE '%sq%' OR LOWER(ph.route) LIKE '%inject%'
        )
        AND ph.entertime BETWEEN ta.admittime AND ta.admittime + INTERVAL 24 HOUR
    )
  ) THEN 1 ELSE 0 END) * 100 AS percent_first_24h,
  AVG(CASE WHEN (
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      WHERE p.hadm_id = ta.hadm_id
        AND (
          LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%byetta%' OR LOWER(p.drug) LIKE '%bydureon%' OR
          LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%victoza%' OR
          LOWER(p.drug) LIKE '%semaglutide%' OR LOWER(p.drug) LIKE '%ozempic%' OR
          LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%trulicity%' OR
          LOWER(p.drug) LIKE '%albiglutide%' OR LOWER(p.drug) LIKE '%tanzeum%' OR
          LOWER(p.drug) LIKE '%lixisenatide%' OR LOWER(p.drug) LIKE '%adlyxin%'
        )
        AND (
          LOWER(p.route) LIKE '%subcut%' OR LOWER(p.route) LIKE '%sc%' OR LOWER(p.route) LIKE '%sq%' OR LOWER(p.route) LIKE '%inject%'
        )
        AND p.starttime BETWEEN ta.dischtime - INTERVAL 12 HOUR AND ta.dischtime
    )
    OR EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
      WHERE ph.hadm_id = ta.hadm_id
        AND (
          LOWER(ph.medication) LIKE '%exenatide%' OR LOWER(ph.medication) LIKE '%byetta%' OR LOWER(ph.medication) LIKE '%bydureon%' OR
          LOWER(ph.medication) LIKE '%liraglutide%' OR LOWER(ph.medication) LIKE '%victoza%' OR
          LOWER(ph.medication) LIKE '%semaglutide%' OR LOWER(ph.medication) LIKE '%ozempic%' OR
          LOWER(ph.medication) LIKE '%dulaglutide%' OR LOWER(ph.medication) LIKE '%trulicity%' OR
          LOWER(ph.medication) LIKE '%albiglutide%' OR LOWER(ph.medication) LIKE '%tanzeum%' OR
          LOWER(ph.medication) LIKE '%lixisenatide%' OR LOWER(ph.medication) LIKE '%adlyxin%'
        )
        AND (
          LOWER(ph.route) LIKE '%subcut%' OR LOWER(ph.route) LIKE '%sc%' OR LOWER(ph.route) LIKE '%sq%' OR LOWER(ph.route) LIKE '%inject%'
        )
        AND ph.entertime BETWEEN ta.dischtime - INTERVAL 12 HOUR AND ta.dischtime
    )
  ) THEN 1 ELSE 0 END) * 100 AS percent_final_12h
FROM target_admissions ta;